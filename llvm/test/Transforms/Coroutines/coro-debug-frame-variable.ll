; RUN: opt < %s -O0 -enable-coroutines -S | FileCheck %s
; RUN: opt < %s -passes='default<O0>' -enable-coroutines -S | FileCheck %s

; Define a function 'f' that resembles the Clang frontend's output for the
; following C++ coroutine:
;
;   void foo() {
;     int i = 0;
;     ++i;
;     print(i);  // Prints '1'
;
;     co_await suspend_always();
;
;     int j = 0;
;     ++i;
;     print(i);  // Prints '2'
;     ++j;
;     print(j);  // Prints '1'
;   }
;
; The CHECKs verify that dbg.declare intrinsics are created for the coroutine
; funclet 'f.resume', and that they reference the address of the variables on
; the coroutine frame.
;
; CHECK-LABEL: define void @f() {
; CHECK:       init.ready:
; CHECK:         [[IGEP:%.+]] = getelementptr inbounds %f.Frame, %f.Frame* %FramePtr, i32 0, i32 4
; CHECK:         call void @llvm.dbg.declare(metadata i32* [[IGEP]], metadata ![[IVAR:[0-9]+]]
; CHECK:       await.ready:
; CHECK:         [[JGEP:%.+]] = getelementptr inbounds %f.Frame, %f.Frame* %FramePtr, i32 0, i32 5
; CHECK:         call void @llvm.dbg.declare(metadata i32* [[JGEP]], metadata ![[JVAR:[0-9]+]]
;
; CHECK-LABEL: define internal fastcc void @f.resume({{.*}}) {
; CHECK:       init.ready:
; CHECK:         [[IGEP_RESUME:%.+]] = getelementptr inbounds %f.Frame, %f.Frame* %FramePtr, i32 0, i32 4
; CHECK:         call void @llvm.dbg.declare(metadata i32* [[IGEP_RESUME]], metadata ![[IVAR_RESUME:[0-9]+]]
; CHECK:       await.ready:
; CHECK:         [[JGEP_RESUME:%.+]] = getelementptr inbounds %f.Frame, %f.Frame* %FramePtr, i32 0, i32 5
; CHECK:         call void @llvm.dbg.declare(metadata i32* [[JGEP_RESUME]], metadata ![[JVAR_RESUME:[0-9]+]]
;
; CHECK: ![[IVAR]] = !DILocalVariable(name: "i"
; CHECK: ![[JVAR]] = !DILocalVariable(name: "j"
; CHECK: ![[IVAR_RESUME]] = !DILocalVariable(name: "i"
; CHECK: ![[JVAR_RESUME]] = !DILocalVariable(name: "j"
define void @f() {
entry:
  %__promise = alloca i8, align 8
  %i = alloca i32, align 4
  %j = alloca i32, align 4
  %id = call token @llvm.coro.id(i32 16, i8* %__promise, i8* null, i8* null)
  %alloc = call i1 @llvm.coro.alloc(token %id)
  br i1 %alloc, label %coro.alloc, label %coro.init

coro.alloc:
  %size = call i64 @llvm.coro.size.i64()
  %memory = call i8* @new(i64 %size)
  br label %coro.init

coro.init:
  %phi.entry.alloc = phi i8* [ null, %entry ], [ %memory, %coro.alloc ]
  %begin = call i8* @llvm.coro.begin(token %id, i8* %phi.entry.alloc)
  %ready = call i1 @await_ready()
  br i1 %ready, label %init.ready, label %init.suspend

init.suspend:
  %save = call token @llvm.coro.save(i8* null)
  call void @await_suspend()
  %suspend = call i8 @llvm.coro.suspend(token %save, i1 false)
  switch i8 %suspend, label %coro.ret [
    i8 0, label %init.ready
    i8 1, label %init.cleanup
  ]

init.cleanup:
  br label %cleanup

init.ready:
  call void @await_resume()
  call void @llvm.dbg.declare(metadata i32* %i, metadata !659, metadata !DIExpression()), !dbg !661
  store i32 0, i32* %i, align 4
  %i.init.ready.load = load i32, i32* %i, align 4
  %i.init.ready.inc = add nsw i32 %i.init.ready.load, 1
  store i32 %i.init.ready.inc, i32* %i, align 4
  %i.init.ready.reload = load i32, i32* %i, align 4
  call void @print(i32 %i.init.ready.reload)
  %ready.again = call zeroext i1 @await_ready()
  br i1 %ready.again, label %await.ready, label %await.suspend

await.suspend:
  %save.again = call token @llvm.coro.save(i8* null)
  %from.address = call i8* @from_address(i8* %begin)
  call void @await_suspend()
  %suspend.again = call i8 @llvm.coro.suspend(token %save.again, i1 false)
  switch i8 %suspend.again, label %coro.ret [
    i8 0, label %await.ready
    i8 1, label %await.cleanup
  ]

await.cleanup:
  br label %cleanup

await.ready:
  call void @await_resume()
  call void @llvm.dbg.declare(metadata i32* %j, metadata !667, metadata !DIExpression()), !dbg !668
  store i32 0, i32* %j, align 4
  %i.await.ready.load = load i32, i32* %i, align 4
  %i.await.ready.inc = add nsw i32 %i.await.ready.load, 1
  store i32 %i.await.ready.inc, i32* %i, align 4
  %j.await.ready.load = load i32, i32* %j, align 4
  %j.await.ready.inc = add nsw i32 %j.await.ready.load, 1
  store i32 %j.await.ready.inc, i32* %j, align 4
  %i.await.ready.reload = load i32, i32* %i, align 4
  call void @print(i32 %i.await.ready.reload)
  %j.await.ready.reload = load i32, i32* %j, align 4
  call void @print(i32 %j.await.ready.reload)
  call void @return_void()
  br label %coro.final

coro.final:
  call void @final_suspend()
  %coro.final.await_ready = call i1 @await_ready()
  br i1 %coro.final.await_ready, label %final.ready, label %final.suspend

final.suspend:
  %final.suspend.coro.save = call token @llvm.coro.save(i8* null)
  %final.suspend.from_address = call i8* @from_address(i8* %begin)
  call void @await_suspend()
  %final.suspend.coro.suspend = call i8 @llvm.coro.suspend(token %final.suspend.coro.save, i1 true)
  switch i8 %final.suspend.coro.suspend, label %coro.ret [
    i8 0, label %final.ready
    i8 1, label %final.cleanup
  ]

final.cleanup:
  br label %cleanup

final.ready:
  call void @await_resume()
  br label %cleanup

cleanup:
  %cleanup.dest.slot.0 = phi i32 [ 0, %final.ready ], [ 2, %final.cleanup ], [ 2, %await.cleanup ], [ 2, %init.cleanup ]
  %free.memory = call i8* @llvm.coro.free(token %id, i8* %begin)
  %free = icmp ne i8* %free.memory, null
  br i1 %free, label %coro.free, label %after.coro.free

coro.free:
  call void @delete(i8* %free.memory)
  br label %after.coro.free

after.coro.free:
  switch i32 %cleanup.dest.slot.0, label %unreachable [
    i32 0, label %cleanup.cont
    i32 2, label %coro.ret
  ]

cleanup.cont:
  br label %coro.ret

coro.ret:
  %end = call i1 @llvm.coro.end(i8* null, i1 false)
  ret void

unreachable:                                      ; preds = %after.coro.free
  unreachable
}

declare void @llvm.dbg.declare(metadata, metadata, metadata)
declare token @llvm.coro.id(i32, i8*, i8*, i8*)
declare i1 @llvm.coro.alloc(token)
declare i64 @llvm.coro.size.i64()
declare token @llvm.coro.save(i8*)
declare i8* @llvm.coro.begin(token, i8*)
declare i8 @llvm.coro.suspend(token, i1)
declare i8* @llvm.coro.free(token, i8*)
declare i1 @llvm.coro.end(i8*, i1)
declare i8* @new(i64)
declare void @delete(i8*)
declare i1 @await_ready()
declare void @await_suspend()
declare void @await_resume()
declare void @print(i32)
declare i8* @from_address(i8*)
declare void @return_void()
declare void @final_suspend()

!llvm.dbg.cu = !{!0}
!llvm.linker.options = !{}
!llvm.module.flags = !{!644, !645, !646}
!llvm.ident = !{!647}

!0 = distinct !DICompileUnit(language: DW_LANG_C_plus_plus_14, file: !1, producer: "clang version 11.0.0 (https://github.com/llvm/llvm-project.git 9d85093c5147ac5b143b64a905b550d3b7f37332)", isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug, enums: !2, retainedTypes: !3, imports: !108, splitDebugInlining: false, nameTableKind: None)
!1 = !DIFile(filename: "/home/modocache/Source/tmp/coro02242020/repro.cpp", directory: "/home/modocache/Source/llvm/git/dev/llvm-project")
!2 = !{}
!3 = !{!4}
!4 = distinct !DICompositeType(tag: DW_TAG_structure_type, name: "coro", file: !5, line: 6, size: 64, flags: DIFlagTypePassByValue | DIFlagNonTrivial, elements: !6, identifier: "_ZTS4coro")
!5 = !DIFile(filename: "tmp/coro02242020/repro.cpp", directory: "/home/modocache/Source")
!6 = !{!7, !104}
!7 = !DIDerivedType(tag: DW_TAG_member, name: "handle", scope: !4, file: !5, line: 18, baseType: !8, size: 64)
!8 = distinct !DICompositeType(tag: DW_TAG_class_type, name: "coroutine_handle<coro::promise_type>", scope: !10, file: !9, line: 196, size: 64, flags: DIFlagTypePassByValue | DIFlagNonTrivial, elements: !13, templateParams: !102, identifier: "_ZTSNSt12experimental13coroutines_v116coroutine_handleIN4coro12promise_typeEEE")
!9 = !DIFile(filename: "build/bin/../include/c++/v1/experimental/coroutine", directory: "/home/modocache/Source/llvm/git/dev/llvm-project")
!10 = !DINamespace(name: "coroutines_v1", scope: !11, exportSymbols: true)
!11 = !DINamespace(name: "experimental", scope: !12)
!12 = !DINamespace(name: "std", scope: null)
!13 = !{!14, !55, !60, !93, !96, !99}
!14 = !DIDerivedType(tag: DW_TAG_inheritance, scope: !8, baseType: !15, flags: DIFlagPublic, extraData: i32 0)
!15 = distinct !DICompositeType(tag: DW_TAG_class_type, name: "coroutine_handle<void>", scope: !10, file: !9, line: 92, size: 64, flags: DIFlagTypePassByValue | DIFlagNonTrivial, elements: !16, templateParams: !53, identifier: "_ZTSNSt12experimental13coroutines_v116coroutine_handleIvEE")
!16 = !{!17, !19, !23, !29, !33, !38, !42, !43, !44, !45, !46, !49, !52}
!17 = !DIDerivedType(tag: DW_TAG_member, name: "__handle_", scope: !15, file: !9, line: 166, baseType: !18, size: 64)
!18 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: null, size: 64)
!19 = !DISubprogram(name: "coroutine_handle", scope: !15, file: !9, line: 95, type: !20, scopeLine: 95, flags: DIFlagPublic | DIFlagPrototyped, spFlags: 0)
!20 = !DISubroutineType(types: !21)
!21 = !{null, !22}
!22 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !15, size: 64, flags: DIFlagArtificial | DIFlagObjectPointer)
!23 = !DISubprogram(name: "coroutine_handle", scope: !15, file: !9, line: 98, type: !24, scopeLine: 98, flags: DIFlagPublic | DIFlagPrototyped, spFlags: 0)
!24 = !DISubroutineType(types: !25)
!25 = !{null, !22, !26}
!26 = !DIDerivedType(tag: DW_TAG_typedef, name: "nullptr_t", scope: !12, file: !27, line: 56, baseType: !28)
!27 = !DIFile(filename: "build/bin/../include/c++/v1/__nullptr", directory: "/home/modocache/Source/llvm/git/dev/llvm-project")
!28 = !DIBasicType(tag: DW_TAG_unspecified_type, name: "decltype(nullptr)")
!29 = !DISubprogram(name: "operator=", linkageName: "_ZNSt12experimental13coroutines_v116coroutine_handleIvEaSEDn", scope: !15, file: !9, line: 101, type: !30, scopeLine: 101, flags: DIFlagPublic | DIFlagPrototyped, spFlags: 0)
!30 = !DISubroutineType(types: !31)
!31 = !{!32, !22, !26}
!32 = !DIDerivedType(tag: DW_TAG_reference_type, baseType: !15, size: 64)
!33 = !DISubprogram(name: "address", linkageName: "_ZNKSt12experimental13coroutines_v116coroutine_handleIvE7addressEv", scope: !15, file: !9, line: 107, type: !34, scopeLine: 107, flags: DIFlagPublic | DIFlagPrototyped, spFlags: 0)
!34 = !DISubroutineType(types: !35)
!35 = !{!18, !36}
!36 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !37, size: 64, flags: DIFlagArtificial | DIFlagObjectPointer)
!37 = !DIDerivedType(tag: DW_TAG_const_type, baseType: !15)
!38 = !DISubprogram(name: "operator bool", linkageName: "_ZNKSt12experimental13coroutines_v116coroutine_handleIvEcvbEv", scope: !15, file: !9, line: 110, type: !39, scopeLine: 110, flags: DIFlagPublic | DIFlagExplicit | DIFlagPrototyped, spFlags: 0)
!39 = !DISubroutineType(types: !40)
!40 = !{!41, !36}
!41 = !DIBasicType(name: "bool", size: 8, encoding: DW_ATE_boolean)
!42 = !DISubprogram(name: "operator()", linkageName: "_ZNSt12experimental13coroutines_v116coroutine_handleIvEclEv", scope: !15, file: !9, line: 113, type: !20, scopeLine: 113, flags: DIFlagPublic | DIFlagPrototyped, spFlags: 0)
!43 = !DISubprogram(name: "resume", linkageName: "_ZNSt12experimental13coroutines_v116coroutine_handleIvE6resumeEv", scope: !15, file: !9, line: 116, type: !20, scopeLine: 116, flags: DIFlagPublic | DIFlagPrototyped, spFlags: 0)
!44 = !DISubprogram(name: "destroy", linkageName: "_ZNSt12experimental13coroutines_v116coroutine_handleIvE7destroyEv", scope: !15, file: !9, line: 125, type: !20, scopeLine: 125, flags: DIFlagPublic | DIFlagPrototyped, spFlags: 0)
!45 = !DISubprogram(name: "done", linkageName: "_ZNKSt12experimental13coroutines_v116coroutine_handleIvE4doneEv", scope: !15, file: !9, line: 132, type: !39, scopeLine: 132, flags: DIFlagPublic | DIFlagPrototyped, spFlags: 0)
!46 = !DISubprogram(name: "from_address", linkageName: "_ZNSt12experimental13coroutines_v116coroutine_handleIvE12from_addressEPv", scope: !15, file: !9, line: 140, type: !47, scopeLine: 140, flags: DIFlagPublic | DIFlagPrototyped | DIFlagStaticMember, spFlags: 0)
!47 = !DISubroutineType(types: !48)
!48 = !{!15, !18}
!49 = !DISubprogram(name: "from_address", linkageName: "_ZNSt12experimental13coroutines_v116coroutine_handleIvE12from_addressEDn", scope: !15, file: !9, line: 148, type: !50, scopeLine: 148, flags: DIFlagPublic | DIFlagPrototyped | DIFlagStaticMember, spFlags: 0)
!50 = !DISubroutineType(types: !51)
!51 = !{!15, !26}
!52 = !DISubprogram(name: "__is_suspended", linkageName: "_ZNKSt12experimental13coroutines_v116coroutine_handleIvE14__is_suspendedEv", scope: !15, file: !9, line: 160, type: !39, scopeLine: 160, flags: DIFlagPrototyped, spFlags: 0)
!53 = !{!54}
!54 = !DITemplateTypeParameter(name: "_Promise", type: null)
!55 = !DISubprogram(name: "operator=", linkageName: "_ZNSt12experimental13coroutines_v116coroutine_handleIN4coro12promise_typeEEaSEDn", scope: !8, file: !9, line: 207, type: !56, scopeLine: 207, flags: DIFlagPublic | DIFlagPrototyped, spFlags: 0)
!56 = !DISubroutineType(types: !57)
!57 = !{!58, !59, !26}
!58 = !DIDerivedType(tag: DW_TAG_reference_type, baseType: !8, size: 64)
!59 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !8, size: 64, flags: DIFlagArtificial | DIFlagObjectPointer)
!60 = !DISubprogram(name: "promise", linkageName: "_ZNKSt12experimental13coroutines_v116coroutine_handleIN4coro12promise_typeEE7promiseEv", scope: !8, file: !9, line: 213, type: !61, scopeLine: 213, flags: DIFlagPublic | DIFlagPrototyped, spFlags: 0)
!61 = !DISubroutineType(types: !62)
!62 = !{!63, !91}
!63 = !DIDerivedType(tag: DW_TAG_reference_type, baseType: !64, size: 64)
!64 = distinct !DICompositeType(tag: DW_TAG_structure_type, name: "promise_type", scope: !4, file: !5, line: 7, size: 8, flags: DIFlagTypePassByValue, elements: !65, identifier: "_ZTSN4coro12promise_typeE")
!65 = !{!66, !70, !86, !87, !90}
!66 = !DISubprogram(name: "get_return_object", linkageName: "_ZN4coro12promise_type17get_return_objectEv", scope: !64, file: !5, line: 8, type: !67, scopeLine: 8, flags: DIFlagPrototyped, spFlags: 0)
!67 = !DISubroutineType(types: !68)
!68 = !{!4, !69}
!69 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !64, size: 64, flags: DIFlagArtificial | DIFlagObjectPointer)
!70 = !DISubprogram(name: "initial_suspend", linkageName: "_ZN4coro12promise_type15initial_suspendEv", scope: !64, file: !5, line: 12, type: !71, scopeLine: 12, flags: DIFlagPrototyped, spFlags: 0)
!71 = !DISubroutineType(types: !72)
!72 = !{!73, !69}
!73 = distinct !DICompositeType(tag: DW_TAG_structure_type, name: "suspend_never", scope: !10, file: !9, line: 300, size: 8, flags: DIFlagTypePassByValue, elements: !74, identifier: "_ZTSNSt12experimental13coroutines_v113suspend_neverE")
!74 = !{!75, !80, !83}
!75 = !DISubprogram(name: "await_ready", linkageName: "_ZNKSt12experimental13coroutines_v113suspend_never11await_readyEv", scope: !73, file: !9, line: 302, type: !76, scopeLine: 302, flags: DIFlagPrototyped, spFlags: 0)
!76 = !DISubroutineType(types: !77)
!77 = !{!41, !78}
!78 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !79, size: 64, flags: DIFlagArtificial | DIFlagObjectPointer)
!79 = !DIDerivedType(tag: DW_TAG_const_type, baseType: !73)
!80 = !DISubprogram(name: "await_suspend", linkageName: "_ZNKSt12experimental13coroutines_v113suspend_never13await_suspendENS0_16coroutine_handleIvEE", scope: !73, file: !9, line: 304, type: !81, scopeLine: 304, flags: DIFlagPrototyped, spFlags: 0)
!81 = !DISubroutineType(types: !82)
!82 = !{null, !78, !15}
!83 = !DISubprogram(name: "await_resume", linkageName: "_ZNKSt12experimental13coroutines_v113suspend_never12await_resumeEv", scope: !73, file: !9, line: 306, type: !84, scopeLine: 306, flags: DIFlagPrototyped, spFlags: 0)
!84 = !DISubroutineType(types: !85)
!85 = !{null, !78}
!86 = !DISubprogram(name: "final_suspend", linkageName: "_ZN4coro12promise_type13final_suspendEv", scope: !64, file: !5, line: 13, type: !71, scopeLine: 13, flags: DIFlagPrototyped, spFlags: 0)
!87 = !DISubprogram(name: "return_void", linkageName: "_ZN4coro12promise_type11return_voidEv", scope: !64, file: !5, line: 14, type: !88, scopeLine: 14, flags: DIFlagPrototyped, spFlags: 0)
!88 = !DISubroutineType(types: !89)
!89 = !{null, !69}
!90 = !DISubprogram(name: "unhandled_exception", linkageName: "_ZN4coro12promise_type19unhandled_exceptionEv", scope: !64, file: !5, line: 15, type: !88, scopeLine: 15, flags: DIFlagPrototyped, spFlags: 0)
!91 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !92, size: 64, flags: DIFlagArtificial | DIFlagObjectPointer)
!92 = !DIDerivedType(tag: DW_TAG_const_type, baseType: !8)
!93 = !DISubprogram(name: "from_address", linkageName: "_ZNSt12experimental13coroutines_v116coroutine_handleIN4coro12promise_typeEE12from_addressEPv", scope: !8, file: !9, line: 220, type: !94, scopeLine: 220, flags: DIFlagPublic | DIFlagPrototyped | DIFlagStaticMember, spFlags: 0)
!94 = !DISubroutineType(types: !95)
!95 = !{!8, !18}
!96 = !DISubprogram(name: "from_address", linkageName: "_ZNSt12experimental13coroutines_v116coroutine_handleIN4coro12promise_typeEE12from_addressEDn", scope: !8, file: !9, line: 231, type: !97, scopeLine: 231, flags: DIFlagPublic | DIFlagPrototyped | DIFlagStaticMember, spFlags: 0)
!97 = !DISubroutineType(types: !98)
!98 = !{!8, !26}
!99 = !DISubprogram(name: "from_promise", linkageName: "_ZNSt12experimental13coroutines_v116coroutine_handleIN4coro12promise_typeEE12from_promiseERS3_", scope: !8, file: !9, line: 250, type: !100, scopeLine: 250, flags: DIFlagPublic | DIFlagPrototyped | DIFlagStaticMember, spFlags: 0)
!100 = !DISubroutineType(types: !101)
!101 = !{!8, !63}
!102 = !{!103}
!103 = !DITemplateTypeParameter(name: "_Promise", type: !64)
!104 = !DISubprogram(name: "coro", scope: !4, file: !5, line: 19, type: !105, scopeLine: 19, flags: DIFlagPrototyped, spFlags: 0)
!105 = !DISubroutineType(types: !106)
!106 = !{null, !107, !8}
!107 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !4, size: 64, flags: DIFlagArtificial | DIFlagObjectPointer)
!108 = !{!109, !116, !122, !126, !132, !134, !142, !146, !153, !155, !159, !163, !167, !173, !175, !179, !183, !187, !189, !193, !197, !201, !203, !205, !207, !212, !219, !225, !230, !236, !240, !244, !246, !248, !250, !254, !258, !262, !266, !270, !274, !278, !282, !286, !290, !292, !296, !298, !300, !303, !304, !308, !310, !314, !320, !327, !332, !334, !338, !342, !348, !353, !358, !362, !366, !370, !375, !377, !382, !386, !390, !394, !398, !402, !407, !411, !413, !417, !419, !427, !431, !436, !440, !444, !448, !452, !454, !458, !465, !469, !473, !480, !482, !484, !486, !493, !497, !500, !503, !508, !512, !515, !518, !522, !525, !528, !531, !534, !537, !540, !543, !545, !547, !549, !551, !553, !555, !557, !559, !561, !563, !566, !569, !571, !576, !580, !584, !588, !590, !592, !596, !598, !602, !604, !608, !613, !617, !621, !625, !627, !629, !631, !633, !635, !639, !643}
!109 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !111, file: !115, line: 107)
!110 = !DINamespace(name: "__1", scope: !12, exportSymbols: true)
!111 = !DIDerivedType(tag: DW_TAG_typedef, name: "FILE", file: !112, line: 7, baseType: !113)
!112 = !DIFile(filename: "/usr/include/x86_64-linux-gnu/bits/types/FILE.h", directory: "")
!113 = !DICompositeType(tag: DW_TAG_structure_type, name: "_IO_FILE", file: !114, line: 49, flags: DIFlagFwdDecl, identifier: "_ZTS8_IO_FILE")
!114 = !DIFile(filename: "/usr/include/x86_64-linux-gnu/bits/types/struct_FILE.h", directory: "")
!115 = !DIFile(filename: "build/bin/../include/c++/v1/cstdio", directory: "/home/modocache/Source/llvm/git/dev/llvm-project")
!116 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !117, file: !115, line: 108)
!117 = !DIDerivedType(tag: DW_TAG_typedef, name: "fpos_t", file: !118, line: 84, baseType: !119)
!118 = !DIFile(filename: "/usr/include/stdio.h", directory: "")
!119 = !DIDerivedType(tag: DW_TAG_typedef, name: "__fpos_t", file: !120, line: 14, baseType: !121)
!120 = !DIFile(filename: "/usr/include/x86_64-linux-gnu/bits/types/__fpos_t.h", directory: "")
!121 = !DICompositeType(tag: DW_TAG_structure_type, name: "_G_fpos_t", file: !120, line: 10, flags: DIFlagFwdDecl, identifier: "_ZTS9_G_fpos_t")
!122 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !123, file: !115, line: 109)
!123 = !DIDerivedType(tag: DW_TAG_typedef, name: "size_t", file: !124, line: 46, baseType: !125)
!124 = !DIFile(filename: "build/lib/clang/11.0.0/include/stddef.h", directory: "/home/modocache/Source/llvm/git/dev/llvm-project")
!125 = !DIBasicType(name: "long unsigned int", size: 64, encoding: DW_ATE_unsigned)
!126 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !127, file: !115, line: 111)
!127 = !DISubprogram(name: "fclose", scope: !118, file: !118, line: 213, type: !128, flags: DIFlagPrototyped, spFlags: 0)
!128 = !DISubroutineType(types: !129)
!129 = !{!130, !131}
!130 = !DIBasicType(name: "int", size: 32, encoding: DW_ATE_signed)
!131 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !111, size: 64)
!132 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !133, file: !115, line: 112)
!133 = !DISubprogram(name: "fflush", scope: !118, file: !118, line: 218, type: !128, flags: DIFlagPrototyped, spFlags: 0)
!134 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !135, file: !115, line: 113)
!135 = !DISubprogram(name: "setbuf", scope: !118, file: !118, line: 304, type: !136, flags: DIFlagPrototyped, spFlags: 0)
!136 = !DISubroutineType(types: !137)
!137 = !{null, !138, !139}
!138 = !DIDerivedType(tag: DW_TAG_restrict_type, baseType: !131)
!139 = !DIDerivedType(tag: DW_TAG_restrict_type, baseType: !140)
!140 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !141, size: 64)
!141 = !DIBasicType(name: "char", size: 8, encoding: DW_ATE_signed_char)
!142 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !143, file: !115, line: 114)
!143 = !DISubprogram(name: "setvbuf", scope: !118, file: !118, line: 308, type: !144, flags: DIFlagPrototyped, spFlags: 0)
!144 = !DISubroutineType(types: !145)
!145 = !{!130, !138, !139, !130, !123}
!146 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !147, file: !115, line: 115)
!147 = !DISubprogram(name: "fprintf", scope: !118, file: !118, line: 326, type: !148, flags: DIFlagPrototyped, spFlags: 0)
!148 = !DISubroutineType(types: !149)
!149 = !{!130, !138, !150, null}
!150 = !DIDerivedType(tag: DW_TAG_restrict_type, baseType: !151)
!151 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !152, size: 64)
!152 = !DIDerivedType(tag: DW_TAG_const_type, baseType: !141)
!153 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !154, file: !115, line: 116)
!154 = !DISubprogram(name: "fscanf", linkageName: "__isoc99_fscanf", scope: !118, file: !118, line: 407, type: !148, flags: DIFlagPrototyped, spFlags: 0)
!155 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !156, file: !115, line: 117)
!156 = !DISubprogram(name: "snprintf", scope: !118, file: !118, line: 354, type: !157, flags: DIFlagPrototyped, spFlags: 0)
!157 = !DISubroutineType(types: !158)
!158 = !{!130, !139, !123, !150, null}
!159 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !160, file: !115, line: 118)
!160 = !DISubprogram(name: "sprintf", scope: !118, file: !118, line: 334, type: !161, flags: DIFlagPrototyped, spFlags: 0)
!161 = !DISubroutineType(types: !162)
!162 = !{!130, !139, !150, null}
!163 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !164, file: !115, line: 119)
!164 = !DISubprogram(name: "sscanf", linkageName: "__isoc99_sscanf", scope: !118, file: !118, line: 412, type: !165, flags: DIFlagPrototyped, spFlags: 0)
!165 = !DISubroutineType(types: !166)
!166 = !{!130, !150, !150, null}
!167 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !168, file: !115, line: 120)
!168 = !DISubprogram(name: "vfprintf", scope: !118, file: !118, line: 341, type: !169, flags: DIFlagPrototyped, spFlags: 0)
!169 = !DISubroutineType(types: !170)
!170 = !{!130, !138, !150, !171}
!171 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !172, size: 64)
!172 = !DICompositeType(tag: DW_TAG_structure_type, name: "__va_list_tag", file: !1, flags: DIFlagFwdDecl, identifier: "_ZTS13__va_list_tag")
!173 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !174, file: !115, line: 121)
!174 = !DISubprogram(name: "vfscanf", linkageName: "__isoc99_vfscanf", scope: !118, file: !118, line: 451, type: !169, flags: DIFlagPrototyped, spFlags: 0)
!175 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !176, file: !115, line: 122)
!176 = !DISubprogram(name: "vsscanf", linkageName: "__isoc99_vsscanf", scope: !118, file: !118, line: 459, type: !177, flags: DIFlagPrototyped, spFlags: 0)
!177 = !DISubroutineType(types: !178)
!178 = !{!130, !150, !150, !171}
!179 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !180, file: !115, line: 123)
!180 = !DISubprogram(name: "vsnprintf", scope: !118, file: !118, line: 358, type: !181, flags: DIFlagPrototyped, spFlags: 0)
!181 = !DISubroutineType(types: !182)
!182 = !{!130, !139, !123, !150, !171}
!183 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !184, file: !115, line: 124)
!184 = !DISubprogram(name: "vsprintf", scope: !118, file: !118, line: 349, type: !185, flags: DIFlagPrototyped, spFlags: 0)
!185 = !DISubroutineType(types: !186)
!186 = !{!130, !139, !150, !171}
!187 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !188, file: !115, line: 125)
!188 = !DISubprogram(name: "fgetc", scope: !118, file: !118, line: 485, type: !128, flags: DIFlagPrototyped, spFlags: 0)
!189 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !190, file: !115, line: 126)
!190 = !DISubprogram(name: "fgets", scope: !118, file: !118, line: 564, type: !191, flags: DIFlagPrototyped, spFlags: 0)
!191 = !DISubroutineType(types: !192)
!192 = !{!140, !139, !130, !138}
!193 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !194, file: !115, line: 127)
!194 = !DISubprogram(name: "fputc", scope: !118, file: !118, line: 521, type: !195, flags: DIFlagPrototyped, spFlags: 0)
!195 = !DISubroutineType(types: !196)
!196 = !{!130, !130, !131}
!197 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !198, file: !115, line: 128)
!198 = !DISubprogram(name: "fputs", scope: !118, file: !118, line: 626, type: !199, flags: DIFlagPrototyped, spFlags: 0)
!199 = !DISubroutineType(types: !200)
!200 = !{!130, !150, !138}
!201 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !202, file: !115, line: 129)
!202 = !DISubprogram(name: "getc", scope: !118, file: !118, line: 486, type: !128, flags: DIFlagPrototyped, spFlags: 0)
!203 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !204, file: !115, line: 130)
!204 = !DISubprogram(name: "putc", scope: !118, file: !118, line: 522, type: !195, flags: DIFlagPrototyped, spFlags: 0)
!205 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !206, file: !115, line: 131)
!206 = !DISubprogram(name: "ungetc", scope: !118, file: !118, line: 639, type: !195, flags: DIFlagPrototyped, spFlags: 0)
!207 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !208, file: !115, line: 132)
!208 = !DISubprogram(name: "fread", scope: !118, file: !118, line: 646, type: !209, flags: DIFlagPrototyped, spFlags: 0)
!209 = !DISubroutineType(types: !210)
!210 = !{!123, !211, !123, !123, !138}
!211 = !DIDerivedType(tag: DW_TAG_restrict_type, baseType: !18)
!212 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !213, file: !115, line: 133)
!213 = !DISubprogram(name: "fwrite", scope: !118, file: !118, line: 652, type: !214, flags: DIFlagPrototyped, spFlags: 0)
!214 = !DISubroutineType(types: !215)
!215 = !{!123, !216, !123, !123, !138}
!216 = !DIDerivedType(tag: DW_TAG_restrict_type, baseType: !217)
!217 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !218, size: 64)
!218 = !DIDerivedType(tag: DW_TAG_const_type, baseType: null)
!219 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !220, file: !115, line: 134)
!220 = !DISubprogram(name: "fgetpos", scope: !118, file: !118, line: 731, type: !221, flags: DIFlagPrototyped, spFlags: 0)
!221 = !DISubroutineType(types: !222)
!222 = !{!130, !138, !223}
!223 = !DIDerivedType(tag: DW_TAG_restrict_type, baseType: !224)
!224 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !117, size: 64)
!225 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !226, file: !115, line: 135)
!226 = !DISubprogram(name: "fseek", scope: !118, file: !118, line: 684, type: !227, flags: DIFlagPrototyped, spFlags: 0)
!227 = !DISubroutineType(types: !228)
!228 = !{!130, !131, !229, !130}
!229 = !DIBasicType(name: "long int", size: 64, encoding: DW_ATE_signed)
!230 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !231, file: !115, line: 136)
!231 = !DISubprogram(name: "fsetpos", scope: !118, file: !118, line: 736, type: !232, flags: DIFlagPrototyped, spFlags: 0)
!232 = !DISubroutineType(types: !233)
!233 = !{!130, !131, !234}
!234 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !235, size: 64)
!235 = !DIDerivedType(tag: DW_TAG_const_type, baseType: !117)
!236 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !237, file: !115, line: 137)
!237 = !DISubprogram(name: "ftell", scope: !118, file: !118, line: 689, type: !238, flags: DIFlagPrototyped, spFlags: 0)
!238 = !DISubroutineType(types: !239)
!239 = !{!229, !131}
!240 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !241, file: !115, line: 138)
!241 = !DISubprogram(name: "rewind", scope: !118, file: !118, line: 694, type: !242, flags: DIFlagPrototyped, spFlags: 0)
!242 = !DISubroutineType(types: !243)
!243 = !{null, !131}
!244 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !245, file: !115, line: 139)
!245 = !DISubprogram(name: "clearerr", scope: !118, file: !118, line: 757, type: !242, flags: DIFlagPrototyped, spFlags: 0)
!246 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !247, file: !115, line: 140)
!247 = !DISubprogram(name: "feof", scope: !118, file: !118, line: 759, type: !128, flags: DIFlagPrototyped, spFlags: 0)
!248 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !249, file: !115, line: 141)
!249 = !DISubprogram(name: "ferror", scope: !118, file: !118, line: 761, type: !128, flags: DIFlagPrototyped, spFlags: 0)
!250 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !251, file: !115, line: 142)
!251 = !DISubprogram(name: "perror", scope: !118, file: !118, line: 775, type: !252, flags: DIFlagPrototyped, spFlags: 0)
!252 = !DISubroutineType(types: !253)
!253 = !{null, !151}
!254 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !255, file: !115, line: 145)
!255 = !DISubprogram(name: "fopen", scope: !118, file: !118, line: 246, type: !256, flags: DIFlagPrototyped, spFlags: 0)
!256 = !DISubroutineType(types: !257)
!257 = !{!131, !150, !150}
!258 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !259, file: !115, line: 146)
!259 = !DISubprogram(name: "freopen", scope: !118, file: !118, line: 252, type: !260, flags: DIFlagPrototyped, spFlags: 0)
!260 = !DISubroutineType(types: !261)
!261 = !{!131, !150, !150, !138}
!262 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !263, file: !115, line: 147)
!263 = !DISubprogram(name: "remove", scope: !118, file: !118, line: 146, type: !264, flags: DIFlagPrototyped, spFlags: 0)
!264 = !DISubroutineType(types: !265)
!265 = !{!130, !151}
!266 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !267, file: !115, line: 148)
!267 = !DISubprogram(name: "rename", scope: !118, file: !118, line: 148, type: !268, flags: DIFlagPrototyped, spFlags: 0)
!268 = !DISubroutineType(types: !269)
!269 = !{!130, !151, !151}
!270 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !271, file: !115, line: 149)
!271 = !DISubprogram(name: "tmpfile", scope: !118, file: !118, line: 173, type: !272, flags: DIFlagPrototyped, spFlags: 0)
!272 = !DISubroutineType(types: !273)
!273 = !{!131}
!274 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !275, file: !115, line: 150)
!275 = !DISubprogram(name: "tmpnam", scope: !118, file: !118, line: 187, type: !276, flags: DIFlagPrototyped, spFlags: 0)
!276 = !DISubroutineType(types: !277)
!277 = !{!140, !140}
!278 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !279, file: !115, line: 154)
!279 = !DISubprogram(name: "getchar", scope: !118, file: !118, line: 492, type: !280, flags: DIFlagPrototyped, spFlags: 0)
!280 = !DISubroutineType(types: !281)
!281 = !{!130}
!282 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !283, file: !115, line: 158)
!283 = !DISubprogram(name: "scanf", linkageName: "__isoc99_scanf", scope: !118, file: !118, line: 410, type: !284, flags: DIFlagPrototyped, spFlags: 0)
!284 = !DISubroutineType(types: !285)
!285 = !{!130, !150, null}
!286 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !287, file: !115, line: 159)
!287 = !DISubprogram(name: "vscanf", linkageName: "__isoc99_vscanf", scope: !118, file: !118, line: 456, type: !288, flags: DIFlagPrototyped, spFlags: 0)
!288 = !DISubroutineType(types: !289)
!289 = !{!130, !150, !171}
!290 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !291, file: !115, line: 163)
!291 = !DISubprogram(name: "printf", scope: !118, file: !118, line: 332, type: !284, flags: DIFlagPrototyped, spFlags: 0)
!292 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !293, file: !115, line: 164)
!293 = !DISubprogram(name: "putchar", scope: !118, file: !118, line: 528, type: !294, flags: DIFlagPrototyped, spFlags: 0)
!294 = !DISubroutineType(types: !295)
!295 = !{!130, !130}
!296 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !297, file: !115, line: 165)
!297 = !DISubprogram(name: "puts", scope: !118, file: !118, line: 632, type: !264, flags: DIFlagPrototyped, spFlags: 0)
!298 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !299, file: !115, line: 166)
!299 = !DISubprogram(name: "vprintf", scope: !118, file: !118, line: 347, type: !288, flags: DIFlagPrototyped, spFlags: 0)
!300 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !301, file: !302, line: 49)
!301 = !DIDerivedType(tag: DW_TAG_typedef, name: "ptrdiff_t", file: !124, line: 35, baseType: !229)
!302 = !DIFile(filename: "build/bin/../include/c++/v1/cstddef", directory: "/home/modocache/Source/llvm/git/dev/llvm-project")
!303 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !123, file: !302, line: 50)
!304 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !305, file: !302, line: 55)
!305 = !DIDerivedType(tag: DW_TAG_typedef, name: "max_align_t", file: !306, line: 24, baseType: !307)
!306 = !DIFile(filename: "build/lib/clang/11.0.0/include/__stddef_max_align_t.h", directory: "/home/modocache/Source/llvm/git/dev/llvm-project")
!307 = !DICompositeType(tag: DW_TAG_structure_type, file: !306, line: 19, flags: DIFlagFwdDecl, identifier: "_ZTS11max_align_t")
!308 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !123, file: !309, line: 99)
!309 = !DIFile(filename: "build/bin/../include/c++/v1/cstdlib", directory: "/home/modocache/Source/llvm/git/dev/llvm-project")
!310 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !311, file: !309, line: 100)
!311 = !DIDerivedType(tag: DW_TAG_typedef, name: "div_t", file: !312, line: 62, baseType: !313)
!312 = !DIFile(filename: "/usr/include/stdlib.h", directory: "")
!313 = !DICompositeType(tag: DW_TAG_structure_type, file: !312, line: 58, flags: DIFlagFwdDecl, identifier: "_ZTS5div_t")
!314 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !315, file: !309, line: 101)
!315 = !DIDerivedType(tag: DW_TAG_typedef, name: "ldiv_t", file: !312, line: 70, baseType: !316)
!316 = distinct !DICompositeType(tag: DW_TAG_structure_type, file: !312, line: 66, size: 128, flags: DIFlagTypePassByValue, elements: !317, identifier: "_ZTS6ldiv_t")
!317 = !{!318, !319}
!318 = !DIDerivedType(tag: DW_TAG_member, name: "quot", scope: !316, file: !312, line: 68, baseType: !229, size: 64)
!319 = !DIDerivedType(tag: DW_TAG_member, name: "rem", scope: !316, file: !312, line: 69, baseType: !229, size: 64, offset: 64)
!320 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !321, file: !309, line: 103)
!321 = !DIDerivedType(tag: DW_TAG_typedef, name: "lldiv_t", file: !312, line: 80, baseType: !322)
!322 = distinct !DICompositeType(tag: DW_TAG_structure_type, file: !312, line: 76, size: 128, flags: DIFlagTypePassByValue, elements: !323, identifier: "_ZTS7lldiv_t")
!323 = !{!324, !326}
!324 = !DIDerivedType(tag: DW_TAG_member, name: "quot", scope: !322, file: !312, line: 78, baseType: !325, size: 64)
!325 = !DIBasicType(name: "long long int", size: 64, encoding: DW_ATE_signed)
!326 = !DIDerivedType(tag: DW_TAG_member, name: "rem", scope: !322, file: !312, line: 79, baseType: !325, size: 64, offset: 64)
!327 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !328, file: !309, line: 105)
!328 = !DISubprogram(name: "atof", scope: !312, file: !312, line: 101, type: !329, flags: DIFlagPrototyped, spFlags: 0)
!329 = !DISubroutineType(types: !330)
!330 = !{!331, !151}
!331 = !DIBasicType(name: "double", size: 64, encoding: DW_ATE_float)
!332 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !333, file: !309, line: 106)
!333 = !DISubprogram(name: "atoi", scope: !312, file: !312, line: 104, type: !264, flags: DIFlagPrototyped, spFlags: 0)
!334 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !335, file: !309, line: 107)
!335 = !DISubprogram(name: "atol", scope: !312, file: !312, line: 107, type: !336, flags: DIFlagPrototyped, spFlags: 0)
!336 = !DISubroutineType(types: !337)
!337 = !{!229, !151}
!338 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !339, file: !309, line: 109)
!339 = !DISubprogram(name: "atoll", scope: !312, file: !312, line: 112, type: !340, flags: DIFlagPrototyped, spFlags: 0)
!340 = !DISubroutineType(types: !341)
!341 = !{!325, !151}
!342 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !343, file: !309, line: 111)
!343 = !DISubprogram(name: "strtod", scope: !312, file: !312, line: 117, type: !344, flags: DIFlagPrototyped, spFlags: 0)
!344 = !DISubroutineType(types: !345)
!345 = !{!331, !150, !346}
!346 = !DIDerivedType(tag: DW_TAG_restrict_type, baseType: !347)
!347 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !140, size: 64)
!348 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !349, file: !309, line: 112)
!349 = !DISubprogram(name: "strtof", scope: !312, file: !312, line: 123, type: !350, flags: DIFlagPrototyped, spFlags: 0)
!350 = !DISubroutineType(types: !351)
!351 = !{!352, !150, !346}
!352 = !DIBasicType(name: "float", size: 32, encoding: DW_ATE_float)
!353 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !354, file: !309, line: 113)
!354 = !DISubprogram(name: "strtold", scope: !312, file: !312, line: 126, type: !355, flags: DIFlagPrototyped, spFlags: 0)
!355 = !DISubroutineType(types: !356)
!356 = !{!357, !150, !346}
!357 = !DIBasicType(name: "long double", size: 128, encoding: DW_ATE_float)
!358 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !359, file: !309, line: 114)
!359 = !DISubprogram(name: "strtol", scope: !312, file: !312, line: 176, type: !360, flags: DIFlagPrototyped, spFlags: 0)
!360 = !DISubroutineType(types: !361)
!361 = !{!229, !150, !346, !130}
!362 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !363, file: !309, line: 116)
!363 = !DISubprogram(name: "strtoll", scope: !312, file: !312, line: 200, type: !364, flags: DIFlagPrototyped, spFlags: 0)
!364 = !DISubroutineType(types: !365)
!365 = !{!325, !150, !346, !130}
!366 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !367, file: !309, line: 118)
!367 = !DISubprogram(name: "strtoul", scope: !312, file: !312, line: 180, type: !368, flags: DIFlagPrototyped, spFlags: 0)
!368 = !DISubroutineType(types: !369)
!369 = !{!125, !150, !346, !130}
!370 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !371, file: !309, line: 120)
!371 = !DISubprogram(name: "strtoull", scope: !312, file: !312, line: 205, type: !372, flags: DIFlagPrototyped, spFlags: 0)
!372 = !DISubroutineType(types: !373)
!373 = !{!374, !150, !346, !130}
!374 = !DIBasicType(name: "long long unsigned int", size: 64, encoding: DW_ATE_unsigned)
!375 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !376, file: !309, line: 122)
!376 = !DISubprogram(name: "rand", scope: !312, file: !312, line: 453, type: !280, flags: DIFlagPrototyped, spFlags: 0)
!377 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !378, file: !309, line: 123)
!378 = !DISubprogram(name: "srand", scope: !312, file: !312, line: 455, type: !379, flags: DIFlagPrototyped, spFlags: 0)
!379 = !DISubroutineType(types: !380)
!380 = !{null, !381}
!381 = !DIBasicType(name: "unsigned int", size: 32, encoding: DW_ATE_unsigned)
!382 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !383, file: !309, line: 124)
!383 = !DISubprogram(name: "calloc", scope: !312, file: !312, line: 542, type: !384, flags: DIFlagPrototyped, spFlags: 0)
!384 = !DISubroutineType(types: !385)
!385 = !{!18, !123, !123}
!386 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !387, file: !309, line: 125)
!387 = !DISubprogram(name: "free", scope: !312, file: !312, line: 565, type: !388, flags: DIFlagPrototyped, spFlags: 0)
!388 = !DISubroutineType(types: !389)
!389 = !{null, !18}
!390 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !391, file: !309, line: 126)
!391 = !DISubprogram(name: "malloc", scope: !312, file: !312, line: 539, type: !392, flags: DIFlagPrototyped, spFlags: 0)
!392 = !DISubroutineType(types: !393)
!393 = !{!18, !123}
!394 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !395, file: !309, line: 127)
!395 = !DISubprogram(name: "realloc", scope: !312, file: !312, line: 550, type: !396, flags: DIFlagPrototyped, spFlags: 0)
!396 = !DISubroutineType(types: !397)
!397 = !{!18, !18, !123}
!398 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !399, file: !309, line: 128)
!399 = !DISubprogram(name: "abort", scope: !312, file: !312, line: 591, type: !400, flags: DIFlagPrototyped | DIFlagNoReturn, spFlags: 0)
!400 = !DISubroutineType(types: !401)
!401 = !{null}
!402 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !403, file: !309, line: 129)
!403 = !DISubprogram(name: "atexit", scope: !312, file: !312, line: 595, type: !404, flags: DIFlagPrototyped, spFlags: 0)
!404 = !DISubroutineType(types: !405)
!405 = !{!130, !406}
!406 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !400, size: 64)
!407 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !408, file: !309, line: 130)
!408 = !DISubprogram(name: "exit", scope: !312, file: !312, line: 617, type: !409, flags: DIFlagPrototyped | DIFlagNoReturn, spFlags: 0)
!409 = !DISubroutineType(types: !410)
!410 = !{null, !130}
!411 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !412, file: !309, line: 131)
!412 = !DISubprogram(name: "_Exit", scope: !312, file: !312, line: 629, type: !409, flags: DIFlagPrototyped | DIFlagNoReturn, spFlags: 0)
!413 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !414, file: !309, line: 133)
!414 = !DISubprogram(name: "getenv", scope: !312, file: !312, line: 634, type: !415, flags: DIFlagPrototyped, spFlags: 0)
!415 = !DISubroutineType(types: !416)
!416 = !{!140, !151}
!417 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !418, file: !309, line: 134)
!418 = !DISubprogram(name: "system", scope: !312, file: !312, line: 784, type: !264, flags: DIFlagPrototyped, spFlags: 0)
!419 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !420, file: !309, line: 136)
!420 = !DISubprogram(name: "bsearch", scope: !312, file: !312, line: 820, type: !421, flags: DIFlagPrototyped, spFlags: 0)
!421 = !DISubroutineType(types: !422)
!422 = !{!18, !217, !217, !123, !123, !423}
!423 = !DIDerivedType(tag: DW_TAG_typedef, name: "__compar_fn_t", file: !312, line: 808, baseType: !424)
!424 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !425, size: 64)
!425 = !DISubroutineType(types: !426)
!426 = !{!130, !217, !217}
!427 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !428, file: !309, line: 137)
!428 = !DISubprogram(name: "qsort", scope: !312, file: !312, line: 830, type: !429, flags: DIFlagPrototyped, spFlags: 0)
!429 = !DISubroutineType(types: !430)
!430 = !{null, !18, !123, !123, !423}
!431 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !432, file: !309, line: 138)
!432 = !DISubprogram(name: "abs", linkageName: "_Z3abse", scope: !433, file: !433, line: 793, type: !434, flags: DIFlagPrototyped, spFlags: 0)
!433 = !DIFile(filename: "build/bin/../include/c++/v1/math.h", directory: "/home/modocache/Source/llvm/git/dev/llvm-project")
!434 = !DISubroutineType(types: !435)
!435 = !{!357, !357}
!436 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !437, file: !309, line: 139)
!437 = !DISubprogram(name: "labs", scope: !312, file: !312, line: 841, type: !438, flags: DIFlagPrototyped, spFlags: 0)
!438 = !DISubroutineType(types: !439)
!439 = !{!229, !229}
!440 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !441, file: !309, line: 141)
!441 = !DISubprogram(name: "llabs", scope: !312, file: !312, line: 844, type: !442, flags: DIFlagPrototyped, spFlags: 0)
!442 = !DISubroutineType(types: !443)
!443 = !{!325, !325}
!444 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !445, file: !309, line: 143)
!445 = !DISubprogram(name: "div", linkageName: "_Z3divxx", scope: !433, file: !433, line: 812, type: !446, flags: DIFlagPrototyped, spFlags: 0)
!446 = !DISubroutineType(types: !447)
!447 = !{!321, !325, !325}
!448 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !449, file: !309, line: 144)
!449 = !DISubprogram(name: "ldiv", scope: !312, file: !312, line: 854, type: !450, flags: DIFlagPrototyped, spFlags: 0)
!450 = !DISubroutineType(types: !451)
!451 = !{!315, !229, !229}
!452 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !453, file: !309, line: 146)
!453 = !DISubprogram(name: "lldiv", scope: !312, file: !312, line: 858, type: !446, flags: DIFlagPrototyped, spFlags: 0)
!454 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !455, file: !309, line: 148)
!455 = !DISubprogram(name: "mblen", scope: !312, file: !312, line: 922, type: !456, flags: DIFlagPrototyped, spFlags: 0)
!456 = !DISubroutineType(types: !457)
!457 = !{!130, !151, !123}
!458 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !459, file: !309, line: 149)
!459 = !DISubprogram(name: "mbtowc", scope: !312, file: !312, line: 925, type: !460, flags: DIFlagPrototyped, spFlags: 0)
!460 = !DISubroutineType(types: !461)
!461 = !{!130, !462, !150, !123}
!462 = !DIDerivedType(tag: DW_TAG_restrict_type, baseType: !463)
!463 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !464, size: 64)
!464 = !DIBasicType(name: "wchar_t", size: 32, encoding: DW_ATE_signed)
!465 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !466, file: !309, line: 150)
!466 = !DISubprogram(name: "wctomb", scope: !312, file: !312, line: 929, type: !467, flags: DIFlagPrototyped, spFlags: 0)
!467 = !DISubroutineType(types: !468)
!468 = !{!130, !140, !464}
!469 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !470, file: !309, line: 151)
!470 = !DISubprogram(name: "mbstowcs", scope: !312, file: !312, line: 933, type: !471, flags: DIFlagPrototyped, spFlags: 0)
!471 = !DISubroutineType(types: !472)
!472 = !{!123, !462, !150, !123}
!473 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !474, file: !309, line: 152)
!474 = !DISubprogram(name: "wcstombs", scope: !312, file: !312, line: 936, type: !475, flags: DIFlagPrototyped, spFlags: 0)
!475 = !DISubroutineType(types: !476)
!476 = !{!123, !139, !477, !123}
!477 = !DIDerivedType(tag: DW_TAG_restrict_type, baseType: !478)
!478 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !479, size: 64)
!479 = !DIDerivedType(tag: DW_TAG_const_type, baseType: !464)
!480 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !481, file: !309, line: 154)
!481 = !DISubprogram(name: "at_quick_exit", scope: !312, file: !312, line: 600, type: !404, flags: DIFlagPrototyped, spFlags: 0)
!482 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !483, file: !309, line: 155)
!483 = !DISubprogram(name: "quick_exit", scope: !312, file: !312, line: 623, type: !409, flags: DIFlagPrototyped | DIFlagNoReturn, spFlags: 0)
!484 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !485, file: !309, line: 158)
!485 = !DISubprogram(name: "aligned_alloc", scope: !312, file: !312, line: 586, type: !384, flags: DIFlagPrototyped, spFlags: 0)
!486 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !487, file: !492, line: 152)
!487 = !DIDerivedType(tag: DW_TAG_typedef, name: "int8_t", file: !488, line: 24, baseType: !489)
!488 = !DIFile(filename: "/usr/include/x86_64-linux-gnu/bits/stdint-intn.h", directory: "")
!489 = !DIDerivedType(tag: DW_TAG_typedef, name: "__int8_t", file: !490, line: 37, baseType: !491)
!490 = !DIFile(filename: "/usr/include/x86_64-linux-gnu/bits/types.h", directory: "")
!491 = !DIBasicType(name: "signed char", size: 8, encoding: DW_ATE_signed_char)
!492 = !DIFile(filename: "build/bin/../include/c++/v1/cstdint", directory: "/home/modocache/Source/llvm/git/dev/llvm-project")
!493 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !494, file: !492, line: 153)
!494 = !DIDerivedType(tag: DW_TAG_typedef, name: "int16_t", file: !488, line: 25, baseType: !495)
!495 = !DIDerivedType(tag: DW_TAG_typedef, name: "__int16_t", file: !490, line: 39, baseType: !496)
!496 = !DIBasicType(name: "short", size: 16, encoding: DW_ATE_signed)
!497 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !498, file: !492, line: 154)
!498 = !DIDerivedType(tag: DW_TAG_typedef, name: "int32_t", file: !488, line: 26, baseType: !499)
!499 = !DIDerivedType(tag: DW_TAG_typedef, name: "__int32_t", file: !490, line: 41, baseType: !130)
!500 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !501, file: !492, line: 155)
!501 = !DIDerivedType(tag: DW_TAG_typedef, name: "int64_t", file: !488, line: 27, baseType: !502)
!502 = !DIDerivedType(tag: DW_TAG_typedef, name: "__int64_t", file: !490, line: 44, baseType: !229)
!503 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !504, file: !492, line: 157)
!504 = !DIDerivedType(tag: DW_TAG_typedef, name: "uint8_t", file: !505, line: 24, baseType: !506)
!505 = !DIFile(filename: "/usr/include/x86_64-linux-gnu/bits/stdint-uintn.h", directory: "")
!506 = !DIDerivedType(tag: DW_TAG_typedef, name: "__uint8_t", file: !490, line: 38, baseType: !507)
!507 = !DIBasicType(name: "unsigned char", size: 8, encoding: DW_ATE_unsigned_char)
!508 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !509, file: !492, line: 158)
!509 = !DIDerivedType(tag: DW_TAG_typedef, name: "uint16_t", file: !505, line: 25, baseType: !510)
!510 = !DIDerivedType(tag: DW_TAG_typedef, name: "__uint16_t", file: !490, line: 40, baseType: !511)
!511 = !DIBasicType(name: "unsigned short", size: 16, encoding: DW_ATE_unsigned)
!512 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !513, file: !492, line: 159)
!513 = !DIDerivedType(tag: DW_TAG_typedef, name: "uint32_t", file: !505, line: 26, baseType: !514)
!514 = !DIDerivedType(tag: DW_TAG_typedef, name: "__uint32_t", file: !490, line: 42, baseType: !381)
!515 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !516, file: !492, line: 160)
!516 = !DIDerivedType(tag: DW_TAG_typedef, name: "uint64_t", file: !505, line: 27, baseType: !517)
!517 = !DIDerivedType(tag: DW_TAG_typedef, name: "__uint64_t", file: !490, line: 45, baseType: !125)
!518 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !519, file: !492, line: 162)
!519 = !DIDerivedType(tag: DW_TAG_typedef, name: "int_least8_t", file: !520, line: 43, baseType: !521)
!520 = !DIFile(filename: "/usr/include/stdint.h", directory: "")
!521 = !DIDerivedType(tag: DW_TAG_typedef, name: "__int_least8_t", file: !490, line: 52, baseType: !489)
!522 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !523, file: !492, line: 163)
!523 = !DIDerivedType(tag: DW_TAG_typedef, name: "int_least16_t", file: !520, line: 44, baseType: !524)
!524 = !DIDerivedType(tag: DW_TAG_typedef, name: "__int_least16_t", file: !490, line: 54, baseType: !495)
!525 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !526, file: !492, line: 164)
!526 = !DIDerivedType(tag: DW_TAG_typedef, name: "int_least32_t", file: !520, line: 45, baseType: !527)
!527 = !DIDerivedType(tag: DW_TAG_typedef, name: "__int_least32_t", file: !490, line: 56, baseType: !499)
!528 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !529, file: !492, line: 165)
!529 = !DIDerivedType(tag: DW_TAG_typedef, name: "int_least64_t", file: !520, line: 46, baseType: !530)
!530 = !DIDerivedType(tag: DW_TAG_typedef, name: "__int_least64_t", file: !490, line: 58, baseType: !502)
!531 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !532, file: !492, line: 167)
!532 = !DIDerivedType(tag: DW_TAG_typedef, name: "uint_least8_t", file: !520, line: 49, baseType: !533)
!533 = !DIDerivedType(tag: DW_TAG_typedef, name: "__uint_least8_t", file: !490, line: 53, baseType: !506)
!534 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !535, file: !492, line: 168)
!535 = !DIDerivedType(tag: DW_TAG_typedef, name: "uint_least16_t", file: !520, line: 50, baseType: !536)
!536 = !DIDerivedType(tag: DW_TAG_typedef, name: "__uint_least16_t", file: !490, line: 55, baseType: !510)
!537 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !538, file: !492, line: 169)
!538 = !DIDerivedType(tag: DW_TAG_typedef, name: "uint_least32_t", file: !520, line: 51, baseType: !539)
!539 = !DIDerivedType(tag: DW_TAG_typedef, name: "__uint_least32_t", file: !490, line: 57, baseType: !514)
!540 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !541, file: !492, line: 170)
!541 = !DIDerivedType(tag: DW_TAG_typedef, name: "uint_least64_t", file: !520, line: 52, baseType: !542)
!542 = !DIDerivedType(tag: DW_TAG_typedef, name: "__uint_least64_t", file: !490, line: 59, baseType: !517)
!543 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !544, file: !492, line: 172)
!544 = !DIDerivedType(tag: DW_TAG_typedef, name: "int_fast8_t", file: !520, line: 58, baseType: !491)
!545 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !546, file: !492, line: 173)
!546 = !DIDerivedType(tag: DW_TAG_typedef, name: "int_fast16_t", file: !520, line: 60, baseType: !229)
!547 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !548, file: !492, line: 174)
!548 = !DIDerivedType(tag: DW_TAG_typedef, name: "int_fast32_t", file: !520, line: 61, baseType: !229)
!549 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !550, file: !492, line: 175)
!550 = !DIDerivedType(tag: DW_TAG_typedef, name: "int_fast64_t", file: !520, line: 62, baseType: !229)
!551 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !552, file: !492, line: 177)
!552 = !DIDerivedType(tag: DW_TAG_typedef, name: "uint_fast8_t", file: !520, line: 71, baseType: !507)
!553 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !554, file: !492, line: 178)
!554 = !DIDerivedType(tag: DW_TAG_typedef, name: "uint_fast16_t", file: !520, line: 73, baseType: !125)
!555 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !556, file: !492, line: 179)
!556 = !DIDerivedType(tag: DW_TAG_typedef, name: "uint_fast32_t", file: !520, line: 74, baseType: !125)
!557 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !558, file: !492, line: 180)
!558 = !DIDerivedType(tag: DW_TAG_typedef, name: "uint_fast64_t", file: !520, line: 75, baseType: !125)
!559 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !560, file: !492, line: 182)
!560 = !DIDerivedType(tag: DW_TAG_typedef, name: "intptr_t", file: !520, line: 87, baseType: !229)
!561 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !562, file: !492, line: 183)
!562 = !DIDerivedType(tag: DW_TAG_typedef, name: "uintptr_t", file: !520, line: 90, baseType: !125)
!563 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !564, file: !492, line: 185)
!564 = !DIDerivedType(tag: DW_TAG_typedef, name: "intmax_t", file: !520, line: 101, baseType: !565)
!565 = !DIDerivedType(tag: DW_TAG_typedef, name: "__intmax_t", file: !490, line: 72, baseType: !229)
!566 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !567, file: !492, line: 186)
!567 = !DIDerivedType(tag: DW_TAG_typedef, name: "uintmax_t", file: !520, line: 102, baseType: !568)
!568 = !DIDerivedType(tag: DW_TAG_typedef, name: "__uintmax_t", file: !490, line: 73, baseType: !125)
!569 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !123, file: !570, line: 68)
!570 = !DIFile(filename: "build/bin/../include/c++/v1/cstring", directory: "/home/modocache/Source/llvm/git/dev/llvm-project")
!571 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !572, file: !570, line: 69)
!572 = !DISubprogram(name: "memcpy", scope: !573, file: !573, line: 42, type: !574, flags: DIFlagPrototyped, spFlags: 0)
!573 = !DIFile(filename: "/usr/include/string.h", directory: "")
!574 = !DISubroutineType(types: !575)
!575 = !{!18, !211, !216, !123}
!576 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !577, file: !570, line: 70)
!577 = !DISubprogram(name: "memmove", scope: !573, file: !573, line: 46, type: !578, flags: DIFlagPrototyped, spFlags: 0)
!578 = !DISubroutineType(types: !579)
!579 = !{!18, !18, !217, !123}
!580 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !581, file: !570, line: 71)
!581 = !DISubprogram(name: "strcpy", scope: !573, file: !573, line: 121, type: !582, flags: DIFlagPrototyped, spFlags: 0)
!582 = !DISubroutineType(types: !583)
!583 = !{!140, !139, !150}
!584 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !585, file: !570, line: 72)
!585 = !DISubprogram(name: "strncpy", scope: !573, file: !573, line: 124, type: !586, flags: DIFlagPrototyped, spFlags: 0)
!586 = !DISubroutineType(types: !587)
!587 = !{!140, !139, !150, !123}
!588 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !589, file: !570, line: 73)
!589 = !DISubprogram(name: "strcat", scope: !573, file: !573, line: 129, type: !582, flags: DIFlagPrototyped, spFlags: 0)
!590 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !591, file: !570, line: 74)
!591 = !DISubprogram(name: "strncat", scope: !573, file: !573, line: 132, type: !586, flags: DIFlagPrototyped, spFlags: 0)
!592 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !593, file: !570, line: 75)
!593 = !DISubprogram(name: "memcmp", scope: !573, file: !573, line: 63, type: !594, flags: DIFlagPrototyped, spFlags: 0)
!594 = !DISubroutineType(types: !595)
!595 = !{!130, !217, !217, !123}
!596 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !597, file: !570, line: 76)
!597 = !DISubprogram(name: "strcmp", scope: !573, file: !573, line: 136, type: !268, flags: DIFlagPrototyped, spFlags: 0)
!598 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !599, file: !570, line: 77)
!599 = !DISubprogram(name: "strncmp", scope: !573, file: !573, line: 139, type: !600, flags: DIFlagPrototyped, spFlags: 0)
!600 = !DISubroutineType(types: !601)
!601 = !{!130, !151, !151, !123}
!602 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !603, file: !570, line: 78)
!603 = !DISubprogram(name: "strcoll", scope: !573, file: !573, line: 143, type: !268, flags: DIFlagPrototyped, spFlags: 0)
!604 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !605, file: !570, line: 79)
!605 = !DISubprogram(name: "strxfrm", scope: !573, file: !573, line: 146, type: !606, flags: DIFlagPrototyped, spFlags: 0)
!606 = !DISubroutineType(types: !607)
!607 = !{!123, !139, !150, !123}
!608 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !609, file: !570, line: 80)
!609 = !DISubprogram(name: "memchr", linkageName: "_Z6memchrUa9enable_ifIXLb1EEEPvim", scope: !610, file: !610, line: 98, type: !611, flags: DIFlagPrototyped, spFlags: 0)
!610 = !DIFile(filename: "build/bin/../include/c++/v1/string.h", directory: "/home/modocache/Source/llvm/git/dev/llvm-project")
!611 = !DISubroutineType(types: !612)
!612 = !{!18, !18, !130, !123}
!613 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !614, file: !570, line: 81)
!614 = !DISubprogram(name: "strchr", linkageName: "_Z6strchrUa9enable_ifIXLb1EEEPci", scope: !610, file: !610, line: 77, type: !615, flags: DIFlagPrototyped, spFlags: 0)
!615 = !DISubroutineType(types: !616)
!616 = !{!140, !140, !130}
!617 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !618, file: !570, line: 82)
!618 = !DISubprogram(name: "strcspn", scope: !573, file: !573, line: 272, type: !619, flags: DIFlagPrototyped, spFlags: 0)
!619 = !DISubroutineType(types: !620)
!620 = !{!123, !151, !151}
!621 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !622, file: !570, line: 83)
!622 = !DISubprogram(name: "strpbrk", linkageName: "_Z7strpbrkUa9enable_ifIXLb1EEEPcPKc", scope: !610, file: !610, line: 84, type: !623, flags: DIFlagPrototyped, spFlags: 0)
!623 = !DISubroutineType(types: !624)
!624 = !{!140, !140, !151}
!625 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !626, file: !570, line: 84)
!626 = !DISubprogram(name: "strrchr", linkageName: "_Z7strrchrUa9enable_ifIXLb1EEEPci", scope: !610, file: !610, line: 91, type: !615, flags: DIFlagPrototyped, spFlags: 0)
!627 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !628, file: !570, line: 85)
!628 = !DISubprogram(name: "strspn", scope: !573, file: !573, line: 276, type: !619, flags: DIFlagPrototyped, spFlags: 0)
!629 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !630, file: !570, line: 86)
!630 = !DISubprogram(name: "strstr", linkageName: "_Z6strstrUa9enable_ifIXLb1EEEPcPKc", scope: !610, file: !610, line: 105, type: !623, flags: DIFlagPrototyped, spFlags: 0)
!631 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !632, file: !570, line: 88)
!632 = !DISubprogram(name: "strtok", scope: !573, file: !573, line: 335, type: !582, flags: DIFlagPrototyped, spFlags: 0)
!633 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !634, file: !570, line: 90)
!634 = !DISubprogram(name: "memset", scope: !573, file: !573, line: 60, type: !611, flags: DIFlagPrototyped, spFlags: 0)
!635 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !636, file: !570, line: 91)
!636 = !DISubprogram(name: "strerror", scope: !573, file: !573, line: 396, type: !637, flags: DIFlagPrototyped, spFlags: 0)
!637 = !DISubroutineType(types: !638)
!638 = !{!140, !130}
!639 = !DIImportedEntity(tag: DW_TAG_imported_declaration, scope: !110, entity: !640, file: !570, line: 92)
!640 = !DISubprogram(name: "strlen", scope: !573, file: !573, line: 384, type: !641, flags: DIFlagPrototyped, spFlags: 0)
!641 = !DISubroutineType(types: !642)
!642 = !{!123, !151}
!643 = !DIImportedEntity(tag: DW_TAG_imported_module, scope: !0, entity: !11, file: !5, line: 4)
!644 = !{i32 7, !"Dwarf Version", i32 4}
!645 = !{i32 2, !"Debug Info Version", i32 3}
!646 = !{i32 1, !"wchar_size", i32 4}
!647 = !{!"clang version 11.0.0 (https://github.com/llvm/llvm-project.git 9d85093c5147ac5b143b64a905b550d3b7f37332)"}
!648 = distinct !DISubprogram(name: "foo", linkageName: "_Z3foov", scope: !5, file: !5, line: 23, type: !649, scopeLine: 23, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !2)
!649 = !DISubroutineType(types: !3)
!650 = !DILocation(line: 23, column: 12, scope: !648)
!651 = !DILocation(line: 23, column: 6, scope: !648)
!654 = !DIDerivedType(tag: DW_TAG_typedef, name: "promise_type", scope: !655, file: !9, line: 79, baseType: !64)
!655 = distinct !DICompositeType(tag: DW_TAG_structure_type, name: "__coroutine_traits_sfinae<coro, void>", scope: !10, file: !9, line: 76, size: 8, flags: DIFlagTypePassByValue, elements: !2, templateParams: !656, identifier: "_ZTSNSt12experimental13coroutines_v125__coroutine_traits_sfinaeI4corovEE")
!656 = !{!657, !658}
!657 = !DITemplateTypeParameter(name: "_Tp", type: !4)
!658 = !DITemplateTypeParameter(type: null)
!659 = !DILocalVariable(name: "i", scope: !660, file: !5, line: 24, type: !130)
!660 = distinct !DILexicalBlock(scope: !648, file: !5, line: 23, column: 12)
!661 = !DILocation(line: 24, column: 7, scope: !660)
!662 = !DILocation(line: 25, column: 3, scope: !660)
!663 = !DILocation(line: 26, column: 18, scope: !660)
!664 = !DILocation(line: 26, column: 3, scope: !660)
!665 = !DILocation(line: 31, column: 12, scope: !660)
!666 = !DILocation(line: 31, column: 3, scope: !660)
!667 = !DILocalVariable(name: "j", scope: !660, file: !5, line: 32, type: !130)
!668 = !DILocation(line: 32, column: 7, scope: !660)
