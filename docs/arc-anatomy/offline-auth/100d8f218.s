==== function 0x100d8f218 (size 0x614)
100d8f218:     	stp	x28, x27, [sp, #-0x60]!
100d8f21c:     	stp	x26, x25, [sp, #0x10]
100d8f220:     	stp	x24, x23, [sp, #0x20]
100d8f224:     	stp	x22, x21, [sp, #0x30]
100d8f228:     	stp	x20, x19, [sp, #0x40]
100d8f22c:     	stp	x29, x30, [sp, #0x50]
100d8f230:     	add	x29, sp, #0x50
100d8f234:     	sub	sp, sp, #0x230
100d8f238:     	mov	x19, sp
100d8f23c:     	mov	x22, x8
100d8f240:     	adrp	x0, 0x10454a000
100d8f244:     	add	x0, x0, #0x138
100d8f248:     	adrp	x1, 0x1036d9000
100d8f24c:     	add	x1, x1, #0xe88
100d8f250:     	bl	0x100005134    ;; CALL:fn:100005134
100d8f254:     	ldur	x8, [x0, #-0x8]
100d8f258:     	ldr	x8, [x8, #0x40]
100d8f25c:     	mov	x9, x8
100d8f260:     	adrp	x16, 0x104197000
100d8f264:     	ldr	x16, [x16, #0x3b0]
100d8f268:     	blr	x16
100d8f26c:     	mov	x9, sp
100d8f270:     	add	x10, x8, #0xf
100d8f274:     	and	x12, x10, #0xfffffffffffffff0
100d8f278:     	sub	x9, x9, x12
100d8f27c:     	str	x9, [x19, #0x20]
100d8f280:     	mov	sp, x9
100d8f284:     	mov	x9, x8
100d8f288:     	adrp	x16, 0x104197000
100d8f28c:     	ldr	x16, [x16, #0x3b0]
100d8f290:     	blr	x16
100d8f294:     	mov	x8, sp
100d8f298:     	sub	x8, x8, x12
100d8f29c:     	str	x8, [x19, #0x10]
100d8f2a0:     	mov	sp, x8
100d8f2a4:     	mov	x0, #0x0                ; =0
100d8f2a8:     	bl	0x1035d2a8c    ;; CALL:stub:_$s10Foundation3URLVMa
100d8f2ac:     	mov	x23, x0
100d8f2b0:     	ldur	x8, [x0, #-0x8]
100d8f2b4:     	str	x8, [x19, #0x38]
100d8f2b8:     	ldr	x8, [x8, #0x40]
100d8f2bc:     	mov	x9, x8
100d8f2c0:     	adrp	x16, 0x104197000
100d8f2c4:     	ldr	x16, [x16, #0x3b0]
100d8f2c8:     	blr	x16
100d8f2cc:     	mov	x9, sp
100d8f2d0:     	add	x10, x8, #0xf
100d8f2d4:     	and	x12, x10, #0xfffffffffffffff0
100d8f2d8:     	sub	x24, x9, x12
100d8f2dc:     	mov	sp, x24
100d8f2e0:     	mov	x9, x8
100d8f2e4:     	adrp	x16, 0x104197000
100d8f2e8:     	ldr	x16, [x16, #0x3b0]
100d8f2ec:     	blr	x16
100d8f2f0:     	mov	x9, sp
100d8f2f4:     	sub	x28, x9, x12
100d8f2f8:     	mov	sp, x28
100d8f2fc:     	mov	x9, x8
100d8f300:     	adrp	x16, 0x104197000
100d8f304:     	ldr	x16, [x16, #0x3b0]
100d8f308:     	blr	x16
100d8f30c:     	mov	x8, sp
100d8f310:     	sub	x26, x8, x12
100d8f314:     	mov	sp, x26
100d8f318:     	adrp	x0, 0x1036d9000
100d8f31c:     	add	x0, x0, #0xfe0
100d8f320:     	bl	0x1035de180    ;; CALL:stub:_swift_getKeyPath
100d8f324:     	adrp	x1, 0x103983000
100d8f328:     	add	x1, x1, #0x5a0    ;; CSTR:/Users/admin/actions-runner/_work/arc/arc/Frameworks/ARCClients/Sources/ApplicationPaths/ApplicationPaths.swift
100d8f32c:     	adrp	x4, 0x103987000
100d8f330:     	add	x4, x4, #0xe00    ;; CSTR:ApplicationPaths/ApplicationPaths.swift
100d8f334:     	sub	x8, x29, #0xa8
100d8f338:     	mov	w2, #0x6f               ; =111
100d8f33c:     	mov	w3, #0x2                ; =2
100d8f340:     	mov	w5, #0x27               ; =39
100d8f344:     	mov	w6, #0x2                ; =2
100d8f348:     	mov	w7, #0x1ac              ; =428
100d8f34c:     	bl	0x1006f2958    ;; CALL:fn:1006f2958
100d8f350:     	bl	0x10059d594    ;; CALL:fn:10059d594
100d8f354:     	ldrb	w8, [x0]
100d8f358:     	cmp	w8, #0x1
100d8f35c:     	stp	x23, x22, [x19, #0x28]
100d8f360:     	str	x24, [x19, #0x8]
100d8f364:     	str	x26, [x19, #0x18]
100d8f368:     	b.ne	0x100d8f38c
100d8f36c:     	bl	0x1035d9848    ;; CALL:stub:_$ss11CommandLineO9argumentsSaySSGvgZ
100d8f370:     	mov	x25, x0
100d8f374:     	bl	0x1007e53e8    ;; CALL:fn:1007e53e8
100d8f378:     	mov	x21, x0
100d8f37c:     	mov	x20, x1
100d8f380:     	mov	x0, x25
100d8f384:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
100d8f388:     	cbnz	x20, 0x100d8f3e0
100d8f38c:     	adrp	x0, 0x10454a000
100d8f390:     	add	x0, x0, #0x228
100d8f394:     	adrp	x1, 0x1036da000
100d8f398:     	add	x1, x1, #0x10
100d8f39c:     	bl	0x100005134    ;; CALL:fn:100005134
100d8f3a0:     	add	x8, x19, #0x68
100d8f3a4:     	sub	x20, x29, #0xa8
100d8f3a8:     	bl	0x1006f2ba0    ;; CALL:fn:1006f2ba0
100d8f3ac:     	ldp	x21, x25, [x19, #0x98]
100d8f3b0:     	mov	x0, x25
100d8f3b4:     	bl	0x1035de3c0    ;; CALL:stub:_swift_retain
100d8f3b8:     	add	x0, x19, #0x68
100d8f3bc:     	bl	0x1000078a4    ;; CALL:fn:1000078a4
100d8f3c0:     	mov	w0, #0x10               ; =16
100d8f3c4:     	mov	x20, x25
100d8f3c8:     	blr	x21
100d8f3cc:     	mov	x21, x0
100d8f3d0:     	mov	x20, x1
100d8f3d4:     	mov	x0, x25
100d8f3d8:     	bl	0x1035de3a8    ;; CALL:stub:_swift_release
100d8f3dc:     	cbz	x20, 0x100d8f400
100d8f3e0:     	mov	x8, x26
100d8f3e4:     	mov	x0, x21
100d8f3e8:     	mov	x1, x20
100d8f3ec:     	mov	w2, #0x1                ; =1
100d8f3f0:     	bl	0x1035d28dc    ;; CALL:stub:_$s10Foundation3URLV15fileURLWithPath11isDirectoryACSSh_SbtcfC
100d8f3f4:     	mov	x0, x20
100d8f3f8:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
100d8f3fc:     	b	0x100d8f470
100d8f400:     	mov	x8, x28
100d8f404:     	mov	x21, #0x0               ; =0
100d8f408:     	bl	0x100d8f0d4    ;; CALL:fn:100d8f0d4
100d8f40c:     	cbnz	x21, 0x100d8f770
100d8f410:     	adrp	x8, 0x1044ac000
100d8f414:     	ldr	x0, [x8, #0xc10]    ;; CLS:NSBundle
100d8f418:     	bl	0x1035dd7b4    ;; CALL:stub:_objc_opt_self
100d8f41c:     	bl	0x1035f4c00    ;; CALL:objc:mainBundle
100d8f420:     	mov	x29, x29
100d8f424:     	bl	0x1035dd7fc    ;; CALL:stub:_objc_retainAutoreleasedReturnValue
100d8f428:     	mov	x20, x0
100d8f42c:     	bl	0x1005a61cc    ;; CALL:fn:1005a61cc
100d8f430:     	mov	x21, x0
100d8f434:     	mov	x25, x1
100d8f438:     	mov	x0, x20
100d8f43c:     	bl	0x1035dd7cc    ;; CALL:stub:_objc_release
100d8f440:     	mov	x0, x21
100d8f444:     	mov	x1, x25
100d8f448:     	mov	x20, x28
100d8f44c:     	bl	0x1035d293c    ;; CALL:stub:_$s10Foundation3URLV19appendPathComponentyySSF
100d8f450:     	mov	x0, x25
100d8f454:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
100d8f458:     	ldr	x8, [x19, #0x38]
100d8f45c:     	ldr	x8, [x8, #0x20]
100d8f460:     	mov	x0, x26
100d8f464:     	mov	x1, x28
100d8f468:     	mov	x2, x23
100d8f46c:     	blr	x8
100d8f470:     	bl	0x1035d9848    ;; CALL:stub:_$ss11CommandLineO9argumentsSaySSGvgZ
100d8f474:     	mov	x21, x0
100d8f478:     	ldr	x8, [x0, #0x10]
100d8f47c:     	str	x8, [x19, #0x40]
100d8f480:     	cbz	x8, 0x100d8f520
100d8f484:     	mov	x27, #0x0               ; =0
100d8f488:     	add	x23, x21, #0x28
100d8f48c:     	adrp	x25, 0x10419c000
100d8f490:     	ldr	x25, [x25, #0xf30]
100d8f494:     	ldr	x8, [x21, #0x10]
100d8f498:     	cmp	x27, x8
100d8f49c:     	b.hs	0x100d8f76c
100d8f4a0:     	ldp	x24, x28, [x23, #-0x8]
100d8f4a4:     	stp	x24, x28, [x19, #0x68]
100d8f4a8:     	mov	x8, #0x2d2d             ; =11565
100d8f4ac:     	movk	x8, #0x6f6c, lsl #16
100d8f4b0:     	movk	x8, #0x2d67, lsl #32
100d8f4b4:     	movk	x8, #0x6966, lsl #48
100d8f4b8:     	str	x8, [x19, #0x50]
100d8f4bc:     	mov	x8, #0x656c             ; =25964
100d8f4c0:     	movk	x8, #0x3d, lsl #16
100d8f4c4:     	movk	x8, #0xeb00, lsl #48    ;; STR:--log-file=
100d8f4c8:     	str	x8, [x19, #0x58]
100d8f4cc:     	bl	0x100d90930    ;; CALL:fn:100d90930
100d8f4d0:     	mov	x22, x0
100d8f4d4:     	bl	0x100d90970    ;; CALL:fn:100d90970
100d8f4d8:     	mov	x26, x0
100d8f4dc:     	mov	x0, x28
100d8f4e0:     	bl	0x1035ddf58    ;; CALL:stub:_swift_bridgeObjectRetain
100d8f4e4:     	add	x0, x19, #0x50
100d8f4e8:     	add	x20, x19, #0x68
100d8f4ec:     	mov	x1, x25
100d8f4f0:     	mov	x2, x25
100d8f4f4:     	mov	x3, x22
100d8f4f8:     	mov	x4, x26
100d8f4fc:     	bl	0x1035d7154    ;; CALL:stub:_$sSK17_StringProcessingSs11SubSequenceRtzrlE6starts4withSbqd___tAA14RegexComponentRd__lF
100d8f500:     	tbnz	w0, #0x0, 0x100d8f670
100d8f504:     	mov	x0, x28
100d8f508:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
100d8f50c:     	add	x27, x27, #0x1
100d8f510:     	add	x23, x23, #0x10
100d8f514:     	ldr	x8, [x19, #0x40]
100d8f518:     	cmp	x8, x27
100d8f51c:     	b.ne	0x100d8f494
100d8f520:     	mov	x0, x21
100d8f524:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
100d8f528:     	adrp	x1, 0x10454a000
100d8f52c:     	add	x1, x1, #0x228
100d8f530:     	adrp	x2, 0x1036da000
100d8f534:     	add	x2, x2, #0x10
100d8f538:     	sub	x0, x29, #0xa8
100d8f53c:     	bl	0x10000733c    ;; CALL:fn:10000733c
100d8f540:     	mov	w1, #0x1                ; =1
100d8f544:     	ldp	x27, x24, [x19, #0x28]
100d8f548:     	ldr	x23, [x19, #0x20]
100d8f54c:     	ldr	x20, [x19, #0x38]
100d8f550:     	ldr	x22, [x19, #0x10]
100d8f554:     	ldr	x21, [x20, #0x38]
100d8f558:     	mov	x0, x22
100d8f55c:     	mov	w2, #0x1                ; =1
100d8f560:     	mov	x3, x27
100d8f564:     	blr	x21
100d8f568:     	mov	x0, x22
100d8f56c:     	mov	x1, x23
100d8f570:     	bl	0x100d909f0    ;; CALL:fn:100d909f0
100d8f574:     	ldr	x8, [x20, #0x30]
100d8f578:     	mov	x0, x23
100d8f57c:     	mov	w1, #0x1                ; =1
100d8f580:     	mov	x2, x27
100d8f584:     	blr	x8
100d8f588:     	cmp	w0, #0x1
100d8f58c:     	b.ne	0x100d8f5e8
100d8f590:     	adrp	x1, 0x10454a000
100d8f594:     	add	x1, x1, #0x138
100d8f598:     	adrp	x2, 0x1036d9000
100d8f59c:     	add	x2, x2, #0xe88
100d8f5a0:     	mov	x0, x23
100d8f5a4:     	bl	0x10000733c    ;; CALL:fn:10000733c
100d8f5a8:     	ldr	x8, [x20, #0x20]
100d8f5ac:     	mov	x0, x24
100d8f5b0:     	ldr	x1, [x19, #0x18]
100d8f5b4:     	mov	x2, x27
100d8f5b8:     	blr	x8
100d8f5bc:     	mov	x0, #0x0                ; =0
100d8f5c0:     	bl	0x100d8fe70    ;; CALL:meta:ApplicationPaths.ApplicationPaths
100d8f5c4:     	mov	x20, x0
100d8f5c8:     	ldrsw	x8, [x0, #0x18]
100d8f5cc:     	add	x0, x24, x8
100d8f5d0:     	mov	w1, #0x1                ; =1
100d8f5d4:     	mov	w2, #0x1                ; =1
100d8f5d8:     	mov	x3, x27
100d8f5dc:     	blr	x21
100d8f5e0:     	mov	w22, #0x0               ; =0
100d8f5e4:     	b	0x100d8f648
100d8f5e8:     	ldr	x22, [x20, #0x20]
100d8f5ec:     	ldr	x25, [x19, #0x8]
100d8f5f0:     	mov	x0, x25
100d8f5f4:     	mov	x1, x23
100d8f5f8:     	mov	x2, x27
100d8f5fc:     	blr	x22
100d8f600:     	mov	x0, x24
100d8f604:     	ldr	x1, [x19, #0x18]
100d8f608:     	mov	x2, x27
100d8f60c:     	blr	x22
100d8f610:     	mov	x0, #0x0                ; =0
100d8f614:     	bl	0x100d8fe70    ;; CALL:meta:ApplicationPaths.ApplicationPaths
100d8f618:     	mov	x20, x0
100d8f61c:     	ldrsw	x23, [x0, #0x18]
100d8f620:     	add	x0, x24, x23
100d8f624:     	mov	x1, x25
100d8f628:     	mov	x2, x27
100d8f62c:     	blr	x22
100d8f630:     	mov	w22, #0x1               ; =1
100d8f634:     	add	x0, x24, x23
100d8f638:     	mov	w1, #0x0                ; =0
100d8f63c:     	mov	w2, #0x1                ; =1
100d8f640:     	mov	x3, x27
100d8f644:     	blr	x21
100d8f648:     	ldrsw	x8, [x20, #0x14]
100d8f64c:     	strb	w22, [x24, x8]
100d8f650:     	sub	sp, x29, #0x50
100d8f654:     	ldp	x29, x30, [sp, #0x50]
100d8f658:     	ldp	x20, x19, [sp, #0x40]
100d8f65c:     	ldp	x22, x21, [sp, #0x30]
100d8f660:     	ldp	x24, x23, [sp, #0x20]
100d8f664:     	ldp	x26, x25, [sp, #0x10]
100d8f668:     	ldp	x28, x27, [sp], #0x60
100d8f66c:     	ret
100d8f670:     	mov	x0, x21
100d8f674:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
100d8f678:     	stp	x24, x28, [x19, #0x68]
100d8f67c:     	bl	0x100d909b0    ;; CALL:fn:100d909b0
100d8f680:     	mov	x5, x0
100d8f684:     	adrp	x4, 0x10419c000
100d8f688:     	ldr	x4, [x4, #0xf30]
100d8f68c:     	add	x20, x19, #0x68
100d8f690:     	mov	w0, #0x3d               ; =61
100d8f694:     	mov	x1, #-0x1f00000000000000 ; =-2233785415175766016    ;; STR:=
100d8f698:     	mov	w2, #0x1                ; =1
100d8f69c:     	mov	w3, #0x1                ; =1
100d8f6a0:     	bl	0x1035d94c4    ;; CALL:stub:_$sSy12RegexBuilderSs11SubSequenceRtzrlE5split9separator9maxSplits25omittingEmptySubsequencesSaySsGSS_SiSbtF
100d8f6a4:     	mov	x20, x0
100d8f6a8:     	mov	x0, x28
100d8f6ac:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
100d8f6b0:     	ldr	x8, [x20, #0x10]
100d8f6b4:     	cmp	x8, #0x1
100d8f6b8:     	ldp	x27, x24, [x19, #0x28]
100d8f6bc:     	ldr	x23, [x19, #0x20]
100d8f6c0:     	b.ls	0x100d8f744
100d8f6c4:     	ldp	x21, x22, [x20, #0x40]
100d8f6c8:     	ldp	x25, x26, [x20, #0x50]
100d8f6cc:     	mov	x0, x26
100d8f6d0:     	mov	w1, #0x2                ; =2
100d8f6d4:     	bl	0x1035ddf64    ;; CALL:stub:_swift_bridgeObjectRetain_n
100d8f6d8:     	mov	x0, x20
100d8f6dc:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
100d8f6e0:     	mov	x0, x21
100d8f6e4:     	mov	x1, x22
100d8f6e8:     	mov	x2, x25
100d8f6ec:     	mov	x3, x26
100d8f6f0:     	bl	0x1035d7604    ;; CALL:stub:_$sSS14_fromSubstringySSSshFZ
100d8f6f4:     	mov	x20, x1
100d8f6f8:     	ldr	x22, [x19, #0x10]
100d8f6fc:     	mov	x8, x22
100d8f700:     	mov	w2, #0x0                ; =0
100d8f704:     	bl	0x1035d28dc    ;; CALL:stub:_$s10Foundation3URLV15fileURLWithPath11isDirectoryACSSh_SbtcfC
100d8f708:     	mov	x0, x26
100d8f70c:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
100d8f710:     	mov	x0, x20
100d8f714:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
100d8f718:     	adrp	x1, 0x10454a000
100d8f71c:     	add	x1, x1, #0x228
100d8f720:     	adrp	x2, 0x1036da000
100d8f724:     	add	x2, x2, #0x10
100d8f728:     	sub	x0, x29, #0xa8
100d8f72c:     	bl	0x10000733c    ;; CALL:fn:10000733c
100d8f730:     	mov	x0, x26
100d8f734:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
100d8f738:     	mov	w1, #0x0                ; =0
100d8f73c:     	ldr	x20, [x19, #0x38]
100d8f740:     	b	0x100d8f554
100d8f744:     	mov	x0, x20
100d8f748:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
100d8f74c:     	adrp	x1, 0x10454a000
100d8f750:     	add	x1, x1, #0x228
100d8f754:     	adrp	x2, 0x1036da000
100d8f758:     	add	x2, x2, #0x10
100d8f75c:     	sub	x0, x29, #0xa8
100d8f760:     	bl	0x10000733c    ;; CALL:fn:10000733c
100d8f764:     	mov	w1, #0x1                ; =1
100d8f768:     	b	0x100d8f54c
100d8f76c:     	brk	#0x1
100d8f770:     	mov	x8, #-0x2000000000000000 ; =-2305843009213693952    ;; STR:
100d8f774:     	stp	xzr, x8, [x19, #0x50]
100d8f778:     	mov	x0, x21
100d8f77c:     	bl	0x1035de0c0    ;; CALL:stub:_swift_errorRetain
100d8f780:     	add	x20, x19, #0x50
100d8f784:     	mov	w0, #0x38               ; =56
100d8f788:     	bl	0x1035d9914    ;; CALL:stub:_$ss11_StringGutsV4growyySiF
100d8f78c:     	ldp	x8, x9, [x19, #0x50]
100d8f790:     	stp	x8, x9, [x19, #0x50]
100d8f794:     	adrp	x8, 0x103987000
100d8f798:     	add	x8, x8, #0xe30    ;; CSTR:Failed to query application support directory. Error: 
100d8f79c:     	sub	x8, x8, #0x20
100d8f7a0:     	orr	x1, x8, #0x8000000000000000
100d8f7a4:     	add	x20, x19, #0x50
100d8f7a8:     	mov	x0, #0x36               ; =54
100d8f7ac:     	movk	x0, #0xd000, lsl #48
100d8f7b0:     	bl	0x1035d7730    ;; CALL:stub:_$sSS6appendyySSF
100d8f7b4:     	str	x21, [x19, #0x48]
100d8f7b8:     	adrp	x0, 0x10454a000
100d8f7bc:     	add	x0, x0, #0x230
100d8f7c0:     	adrp	x1, 0x1036da000
100d8f7c4:     	add	x1, x1, #0x18
100d8f7c8:     	bl	0x100005134    ;; CALL:fn:100005134
100d8f7cc:     	mov	x2, x0
100d8f7d0:     	adrp	x3, 0x10419e000
100d8f7d4:     	ldr	x3, [x3, #0xc48]
100d8f7d8:     	adrp	x4, 0x10419e000
100d8f7dc:     	ldr	x4, [x4, #0xc58]
100d8f7e0:     	add	x0, x19, #0x48
100d8f7e4:     	add	x1, x19, #0x50
100d8f7e8:     	bl	0x1035d9d4c    ;; CALL:stub:_$ss15_print_unlockedyyx_q_zts16TextOutputStreamR_r0_lF
100d8f7ec:     	ldp	x3, x4, [x19, #0x50]
100d8f7f0:     	sub	sp, sp, #0x10
100d8f7f4:     	str	wzr, [sp, #0x8]
100d8f7f8:     	mov	w8, #0x1c8              ; =456
100d8f7fc:     	str	x8, [sp]
100d8f800:     	adrp	x0, 0x103952000
100d8f804:     	add	x0, x0, #0xaa0    ;; CSTR:Fatal error
100d8f808:     	adrp	x5, 0x103987000
100d8f80c:     	add	x5, x5, #0xe00    ;; CSTR:ApplicationPaths/ApplicationPaths.swift
100d8f810:     	mov	w1, #0xb                ; =11
100d8f814:     	mov	w2, #0x2                ; =2
100d8f818:     	mov	w6, #0x27               ; =39
100d8f81c:     	mov	w7, #0x2                ; =2
100d8f820:     	bl	0x1035d9fbc    ;; CALL:stub:_$ss17_assertionFailure__4file4line5flagss5NeverOs12StaticStringV_SSAHSus6UInt32VtF
100d8f824:     	add	sp, sp, #0x10
100d8f828:     	brk	#0x1
