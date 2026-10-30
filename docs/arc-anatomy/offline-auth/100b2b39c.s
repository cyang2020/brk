==== function 0x100b2b39c (size 0x170)
100b2b39c:     	stp	x22, x21, [sp, #-0x30]!
100b2b3a0:     	stp	x20, x19, [sp, #0x10]
100b2b3a4:     	stp	x29, x30, [sp, #0x20]
100b2b3a8:     	add	x29, sp, #0x20
100b2b3ac:     	adrp	x8, 0x104538000
100b2b3b0:     	ldr	x8, [x8, #0xb10]
100b2b3b4:     	cmn	x8, #0x1
100b2b3b8:     	b.ne	0x100b2b4f4
100b2b3bc:     	adrp	x8, 0x104653000
100b2b3c0:     	ldrb	w8, [x8, #0x110]
100b2b3c4:     	cmp	w8, #0x1
100b2b3c8:     	b.ne	0x100b2b4a8
100b2b3cc:     	adrp	x8, 0x1044ac000
100b2b3d0:     	ldr	x0, [x8, #0xc18]    ;; CLS:NSProcessInfo
100b2b3d4:     	bl	0x1035dd7b4    ;; CALL:stub:_objc_opt_self
100b2b3d8:     	bl	0x1035f88c0    ;; CALL:objc:processInfo
100b2b3dc:     	mov	x29, x29
100b2b3e0:     	bl	0x1035dd7fc    ;; CALL:stub:_objc_retainAutoreleasedReturnValue
100b2b3e4:     	mov	x19, x0
100b2b3e8:     	bl	0x1035ea040    ;; CALL:objc:environment
100b2b3ec:     	mov	x29, x29
100b2b3f0:     	bl	0x1035dd7fc    ;; CALL:stub:_objc_retainAutoreleasedReturnValue
100b2b3f4:     	mov	x21, x0
100b2b3f8:     	mov	x0, x19
100b2b3fc:     	bl	0x1035dd7cc    ;; CALL:stub:_objc_release
100b2b400:     	adrp	x1, 0x10419c000
100b2b404:     	ldr	x1, [x1, #0xf30]
100b2b408:     	adrp	x3, 0x10419c000
100b2b40c:     	ldr	x3, [x3, #0xf40]
100b2b410:     	mov	x0, x21
100b2b414:     	mov	x2, x1
100b2b418:     	bl	0x1035d6e18    ;; CALL:stub:_$sSD10FoundationE36_unconditionallyBridgeFromObjectiveCySDyxq_GSo12NSDictionaryCSgFZ
100b2b41c:     	mov	x20, x0
100b2b420:     	mov	x0, x21
100b2b424:     	bl	0x1035dd7cc    ;; CALL:stub:_objc_release
100b2b428:     	ldr	x8, [x20, #0x10]
100b2b42c:     	cbz	x8, 0x100b2b4b0
100b2b430:     	adrp	x8, 0x10397d000
100b2b434:     	add	x8, x8, #0x560    ;; CSTR:ARC_AUTH_UI_TEST_SKIP_USER_CREATION
100b2b438:     	sub	x19, x8, #0x20
100b2b43c:     	mov	x0, x20
100b2b440:     	bl	0x1035ddf58    ;; CALL:stub:_swift_bridgeObjectRetain
100b2b444:     	orr	x1, x19, #0x8000000000000000
100b2b448:     	mov	x0, #0x23               ; =35
100b2b44c:     	movk	x0, #0xd000, lsl #48
100b2b450:     	bl	0x100004f58    ;; CALL:fn:100004f58
100b2b454:     	tbz	w1, #0x0, 0x100b2b4b8
100b2b458:     	ldr	x8, [x20, #0x38]
100b2b45c:     	add	x8, x8, x0, lsl #4
100b2b460:     	ldp	x21, x19, [x8]
100b2b464:     	mov	x0, x19
100b2b468:     	bl	0x1035ddf58    ;; CALL:stub:_swift_bridgeObjectRetain
100b2b46c:     	mov	x0, x20
100b2b470:     	mov	w1, #0x2                ; =2
100b2b474:     	bl	0x1035ddf4c    ;; CALL:stub:_swift_bridgeObjectRelease_n
100b2b478:     	cmp	x21, #0x31
100b2b47c:     	mov	x8, #-0x1f00000000000000 ; =-2233785415175766016
100b2b480:     	ccmp	x19, x8, #0x0, eq
100b2b484:     	b.eq	0x100b2b4c8
100b2b488:     	mov	x0, x21
100b2b48c:     	mov	x1, x19
100b2b490:     	mov	w2, #0x31               ; =49
100b2b494:     	mov	x3, #-0x1f00000000000000 ; =-2233785415175766016    ;; STR:1
100b2b498:     	mov	w4, #0x0                ; =0
100b2b49c:     	bl	0x1035da838    ;; CALL:stub:_$ss27_stringCompareWithSmolCheck__9expectingSbs11_StringGutsV_ADs01_G16ComparisonResultOtF
100b2b4a0:     	mov	x21, x0
100b2b4a4:     	b	0x100b2b4cc
100b2b4a8:     	mov	w21, #0x0               ; =0
100b2b4ac:     	b	0x100b2b4d8
100b2b4b0:     	mov	w21, #0x0               ; =0
100b2b4b4:     	b	0x100b2b4d0
100b2b4b8:     	mov	x0, x20
100b2b4bc:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
100b2b4c0:     	mov	w21, #0x0               ; =0
100b2b4c4:     	b	0x100b2b4d0
100b2b4c8:     	mov	w21, #0x1               ; =1
100b2b4cc:     	mov	x20, x19
100b2b4d0:     	mov	x0, x20
100b2b4d4:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
100b2b4d8:     	and	w8, w21, #0x1
100b2b4dc:     	adrp	x9, 0x104653000
100b2b4e0:     	strb	w8, [x9, #0x111]
100b2b4e4:     	ldp	x29, x30, [sp, #0x20]
100b2b4e8:     	ldp	x20, x19, [sp, #0x10]
100b2b4ec:     	ldp	x22, x21, [sp], #0x30
100b2b4f0:     	ret
100b2b4f4:     	adrp	x0, 0x104538000
100b2b4f8:     	add	x0, x0, #0xb10
100b2b4fc:     	adrp	x1, 0x100b2b000
100b2b500:     	add	x1, x1, #0x15c
100b2b504:     	bl	0x1035de348    ;; CALL:stub:_swift_once
100b2b508:     	b	0x100b2b3bc
