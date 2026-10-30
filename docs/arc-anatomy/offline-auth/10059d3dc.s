==== function 0x10059d3dc (size 0x1b8)
10059d3dc:     	sub	sp, sp, #0x40
10059d3e0:     	stp	x22, x21, [sp, #0x10]
10059d3e4:     	stp	x20, x19, [sp, #0x20]
10059d3e8:     	stp	x29, x30, [sp, #0x30]
10059d3ec:     	add	x29, sp, #0x30
10059d3f0:     	mov	x22, #0x14              ; =20
10059d3f4:     	movk	x22, #0xd000, lsl #48
10059d3f8:     	adrp	x8, 0x1044ac000
10059d3fc:     	ldr	x0, [x8, #0xc10]    ;; CLS:NSBundle
10059d400:     	bl	0x1035dd7b4    ;; CALL:stub:_objc_opt_self
10059d404:     	bl	0x1035f4c00    ;; CALL:objc:mainBundle
10059d408:     	mov	x29, x29
10059d40c:     	bl	0x1035dd7fc    ;; CALL:stub:_objc_retainAutoreleasedReturnValue
10059d410:     	mov	x19, x0
10059d414:     	bl	0x1035e2da0    ;; CALL:objc:bundleIdentifier
10059d418:     	mov	x29, x29
10059d41c:     	bl	0x1035dd7fc    ;; CALL:stub:_objc_retainAutoreleasedReturnValue
10059d420:     	mov	x20, x0
10059d424:     	mov	x0, x19
10059d428:     	bl	0x1035dd7cc    ;; CALL:stub:_objc_release
10059d42c:     	cbz	x20, 0x10059d44c
10059d430:     	mov	x0, x20
10059d434:     	bl	0x1035d7400    ;; CALL:stub:_$sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ
10059d438:     	mov	x21, x0
10059d43c:     	mov	x19, x1
10059d440:     	mov	x0, x20
10059d444:     	bl	0x1035dd7cc    ;; CALL:stub:_objc_release
10059d448:     	b	0x10059d4f8
10059d44c:     	adrp	x8, 0x1044ac000
10059d450:     	ldr	x0, [x8, #0xc18]    ;; CLS:NSProcessInfo
10059d454:     	bl	0x1035dd7b4    ;; CALL:stub:_objc_opt_self
10059d458:     	bl	0x1035f88c0    ;; CALL:objc:processInfo
10059d45c:     	mov	x29, x29
10059d460:     	bl	0x1035dd7fc    ;; CALL:stub:_objc_retainAutoreleasedReturnValue
10059d464:     	mov	x19, x0
10059d468:     	bl	0x1035ea040    ;; CALL:objc:environment
10059d46c:     	mov	x29, x29
10059d470:     	bl	0x1035dd7fc    ;; CALL:stub:_objc_retainAutoreleasedReturnValue
10059d474:     	mov	x21, x0
10059d478:     	mov	x0, x19
10059d47c:     	bl	0x1035dd7cc    ;; CALL:stub:_objc_release
10059d480:     	adrp	x1, 0x10419c000
10059d484:     	ldr	x1, [x1, #0xf30]
10059d488:     	adrp	x3, 0x10419c000
10059d48c:     	ldr	x3, [x3, #0xf40]
10059d490:     	mov	x0, x21
10059d494:     	mov	x2, x1
10059d498:     	bl	0x1035d6e18    ;; CALL:stub:_$sSD10FoundationE36_unconditionallyBridgeFromObjectiveCySDyxq_GSo12NSDictionaryCSgFZ
10059d49c:     	mov	x20, x0
10059d4a0:     	mov	x0, x21
10059d4a4:     	bl	0x1035dd7cc    ;; CALL:stub:_objc_release
10059d4a8:     	ldr	x8, [x20, #0x10]
10059d4ac:     	cbz	x8, 0x10059d544
10059d4b0:     	adrp	x8, 0x103968000
10059d4b4:     	add	x8, x8, #0x430    ;; CSTR:__CFBundleIdentifier
10059d4b8:     	sub	x19, x8, #0x20
10059d4bc:     	mov	x0, x20
10059d4c0:     	bl	0x1035ddf58    ;; CALL:stub:_swift_bridgeObjectRetain
10059d4c4:     	orr	x1, x19, #0x8000000000000000
10059d4c8:     	mov	x0, #0x14               ; =20
10059d4cc:     	movk	x0, #0xd000, lsl #48
10059d4d0:     	bl	0x100004f58    ;; CALL:fn:100004f58
10059d4d4:     	tbz	w1, #0x0, 0x10059d53c
10059d4d8:     	ldr	x8, [x20, #0x38]
10059d4dc:     	add	x8, x8, x0, lsl #4
10059d4e0:     	ldp	x21, x19, [x8]
10059d4e4:     	mov	x0, x19
10059d4e8:     	bl	0x1035ddf58    ;; CALL:stub:_swift_bridgeObjectRetain
10059d4ec:     	mov	x0, x20
10059d4f0:     	mov	w1, #0x2                ; =2
10059d4f4:     	bl	0x1035ddf4c    ;; CALL:stub:_swift_bridgeObjectRelease_n
10059d4f8:     	adrp	x8, 0x103968000
10059d4fc:     	add	x8, x8, #0x4d0    ;; CSTR:company.thebrowser.dia
10059d500:     	sub	x8, x8, #0x20
10059d504:     	add	x0, x22, #0x2
10059d508:     	orr	x1, x8, #0x8000000000000000
10059d50c:     	mov	x2, x21
10059d510:     	mov	x3, x19
10059d514:     	bl	0x1035d7844    ;; CALL:stub:_$sSS9hasPrefixySbSSF
10059d518:     	mov	x20, x0
10059d51c:     	mov	x0, x19
10059d520:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
10059d524:     	and	w0, w20, #0x1
10059d528:     	ldp	x29, x30, [sp, #0x30]
10059d52c:     	ldp	x20, x19, [sp, #0x20]
10059d530:     	ldp	x22, x21, [sp, #0x10]
10059d534:     	add	sp, sp, #0x40
10059d538:     	ret
10059d53c:     	mov	x0, x20
10059d540:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
10059d544:     	mov	x0, x20
10059d548:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
10059d54c:     	adrp	x8, 0x103968000
10059d550:     	add	x8, x8, #0x480    ;; CSTR:Unable to locate bundle identifier to determine application type!
10059d554:     	sub	x8, x8, #0x20
10059d558:     	str	wzr, [sp, #0x8]
10059d55c:     	mov	w9, #0x13               ; =19
10059d560:     	str	x9, [sp]
10059d564:     	adrp	x0, 0x103952000
10059d568:     	add	x0, x0, #0xaa0    ;; CSTR:Fatal error
10059d56c:     	adrp	x5, 0x103968000
10059d570:     	add	x5, x5, #0x450    ;; CSTR:ARCFoundationModels/AppEnvironment.swift
10059d574:     	add	x3, x22, #0x2d
10059d578:     	orr	x4, x8, #0x8000000000000000
10059d57c:     	mov	w1, #0xb                ; =11
10059d580:     	mov	w2, #0x2                ; =2
10059d584:     	mov	w6, #0x28               ; =40
10059d588:     	mov	w7, #0x2                ; =2
10059d58c:     	bl	0x1035d9fbc    ;; CALL:stub:_$ss17_assertionFailure__4file4line5flagss5NeverOs12StaticStringV_SSAHSus6UInt32VtF
10059d590:     	brk	#0x1
