==== function 0x1000035a4 (size 0x538)
1000035a4:     	stp	x28, x27, [sp, #-0x60]!
1000035a8:     	stp	x26, x25, [sp, #0x10]
1000035ac:     	stp	x24, x23, [sp, #0x20]
1000035b0:     	stp	x22, x21, [sp, #0x30]
1000035b4:     	stp	x20, x19, [sp, #0x40]
1000035b8:     	stp	x29, x30, [sp, #0x50]
1000035bc:     	add	x29, sp, #0x50
1000035c0:     	sub	sp, sp, #0x50
1000035c4:     	mov	x0, #0x0                ; =0
1000035c8:     	bl	0x100d8fe70    ;; CALL:meta:ApplicationPaths.ApplicationPaths
1000035cc:     	ldur	x8, [x0, #-0x8]
1000035d0:     	ldr	x8, [x8, #0x40]
1000035d4:     	mov	x9, x8
1000035d8:     	adrp	x16, 0x104197000
1000035dc:     	ldr	x16, [x16, #0x3b0]
1000035e0:     	blr	x16
1000035e4:     	mov	x9, sp
1000035e8:     	add	x8, x8, #0xf
1000035ec:     	and	x8, x8, #0xfffffffffffffff0
1000035f0:     	sub	x24, x9, x8
1000035f4:     	mov	sp, x24
1000035f8:     	mov	x0, #0x0                ; =0
1000035fc:     	bl	0x1035d2a8c    ;; CALL:stub:_$s10Foundation3URLVMa
100003600:     	mov	x21, x0
100003604:     	ldur	x26, [x0, #-0x8]
100003608:     	ldr	x8, [x26, #0x40]
10000360c:     	mov	x9, x8
100003610:     	adrp	x16, 0x104197000
100003614:     	ldr	x16, [x16, #0x3b0]
100003618:     	blr	x16
10000361c:     	mov	x9, sp
100003620:     	add	x10, x8, #0xf
100003624:     	and	x12, x10, #0xfffffffffffffff0
100003628:     	sub	x23, x9, x12
10000362c:     	mov	sp, x23
100003630:     	mov	x9, x8
100003634:     	adrp	x16, 0x104197000
100003638:     	ldr	x16, [x16, #0x3b0]
10000363c:     	blr	x16
100003640:     	mov	x8, sp
100003644:     	sub	x22, x8, x12
100003648:     	mov	sp, x22
10000364c:     	mov	x0, #0x0                ; =0
100003650:     	bl	0x1004c4268    ;; CALL:meta:ADK.ADKApplication
100003654:     	mov	x20, x0
100003658:     	bl	0x1004abb3c    ;; CALL:fn:1004abb3c
10000365c:     	mov	x19, x0
100003660:     	adrp	x8, 0x104651000
100003664:     	ldrb	w8, [x8, #0x290]
100003668:     	tbnz	w8, #0x0, 0x1000038c8
10000366c:     	bl	0x1035d9848    ;; CALL:stub:_$ss11CommandLineO9argumentsSaySSGvgZ
100003670:     	mov	x20, x0
100003674:     	bl	0x1004a5600    ;; CALL:fn:1004a5600
100003678:     	mov	x0, x20
10000367c:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
100003680:     	bl	0x10008b090    ;; CALL:fn:10008b090
100003684:     	bl	0x10008b2b4    ;; CALL:fn:10008b2b4
100003688:     	bl	0x100d8f82c    ;; CALL:fn:100d8f82c
10000368c:     	mov	x1, x24
100003690:     	bl	0x100005068    ;; CALL:fn:100005068
100003694:     	mov	x8, x22
100003698:     	mov	w0, #0x0                ; =0
10000369c:     	mov	x20, x24
1000036a0:     	bl	0x100d8df98    ;; CALL:fn:100d8df98
1000036a4:     	mov	x0, x24
1000036a8:     	bl	0x1000050ac    ;; CALL:fn:1000050ac
1000036ac:     	bl	0x100d98d10    ;; CALL:fn:100d98d10
1000036b0:     	ldp	x20, x23, [x0]
1000036b4:     	ldr	x8, [x19]
1000036b8:     	adrp	x25, 0x10419f000
1000036bc:     	ldr	x25, [x25, #0xa18]
1000036c0:     	ldr	x9, [x25]
1000036c4:     	and	x8, x9, x8
1000036c8:     	ldr	x24, [x8, #0x3b8]
1000036cc:     	mov	x0, x23
1000036d0:     	bl	0x1035ddf58    ;; CALL:stub:_swift_bridgeObjectRetain
1000036d4:     	stp	xzr, xzr, [sp, #-0x20]!
1000036d8:     	mov	w8, #0x1                ; =1
1000036dc:     	strh	w8, [sp, #0x10]
1000036e0:     	mov	x0, x22
1000036e4:     	mov	x1, #0x0                ; =0
1000036e8:     	mov	x2, #0x0                ; =0
1000036ec:     	mov	w3, #0x1                ; =1
1000036f0:     	mov	x4, #0x0                ; =0
1000036f4:     	mov	w5, #0x0                ; =0
1000036f8:     	mov	x6, x20
1000036fc:     	mov	x7, x23
100003700:     	mov	x20, x19
100003704:     	blr	x24
100003708:     	add	sp, sp, #0x20
10000370c:     	mov	x20, x1
100003710:     	mov	x24, x2
100003714:     	mov	x0, x23
100003718:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
10000371c:     	ldr	x8, [x26, #0x8]
100003720:     	mov	x0, x22
100003724:     	mov	x1, x21
100003728:     	blr	x8
10000372c:     	ands	w8, w24, #0xff
100003730:     	b.ne	0x1000038b8
100003734:     	bl	0x100b2ad10    ;; CALL:fn:100b2ad10
100003738:     	ldrb	w8, [x0]
10000373c:     	tbz	w8, #0x0, 0x100003758
100003740:     	ldr	x8, [x19]
100003744:     	ldr	x9, [x25]
100003748:     	and	x8, x9, x8
10000374c:     	ldr	x8, [x8, #0x490]
100003750:     	mov	x20, x19
100003754:     	blr	x8
100003758:     	adrp	x8, 0x104651000
10000375c:     	ldr	x21, [x8, #0x298]
100003760:     	mov	x0, x21
100003764:     	bl	0x1035ee660    ;; CALL:objc:infoDictionary
100003768:     	mov	x29, x29
10000376c:     	bl	0x1035dd7fc    ;; CALL:stub:_objc_retainAutoreleasedReturnValue
100003770:     	cbz	x0, 0x100003ac4
100003774:     	adrp	x23, 0x10419f000
100003778:     	ldr	x23, [x23, #0x718]
10000377c:     	adrp	x1, 0x10419c000
100003780:     	ldr	x1, [x1, #0xf30]
100003784:     	adrp	x3, 0x10419c000
100003788:     	ldr	x3, [x3, #0xf40]
10000378c:     	add	x2, x23, #0x8
100003790:     	mov	x22, x0
100003794:     	bl	0x1035d6e18    ;; CALL:stub:_$sSD10FoundationE36_unconditionallyBridgeFromObjectiveCySDyxq_GSo12NSDictionaryCSgFZ
100003798:     	mov	x20, x0
10000379c:     	mov	x0, x22
1000037a0:     	bl	0x1035dd7cc    ;; CALL:stub:_objc_release
1000037a4:     	ldr	x8, [x20, #0x10]
1000037a8:     	cbz	x8, 0x100003800
1000037ac:     	mov	x0, x20
1000037b0:     	bl	0x1035ddf58    ;; CALL:stub:_swift_bridgeObjectRetain
1000037b4:     	mov	x0, #0x534e             ; =21326
1000037b8:     	movk	x0, #0x614d, lsl #16
1000037bc:     	movk	x0, #0x6e69, lsl #32
1000037c0:     	movk	x0, #0x694e, lsl #48
1000037c4:     	mov	x1, #0x4662             ; =18018
1000037c8:     	movk	x1, #0x6c69, lsl #16
1000037cc:     	movk	x1, #0x65, lsl #32
1000037d0:     	movk	x1, #0xed00, lsl #48    ;; STR:NSMainNibFile
1000037d4:     	bl	0x100004f58    ;; CALL:fn:100004f58
1000037d8:     	tbz	w1, #0x0, 0x1000037f8
1000037dc:     	ldr	x8, [x20, #0x38]
1000037e0:     	add	x0, x8, x0, lsl #5
1000037e4:     	sub	x1, x29, #0x90
1000037e8:     	bl	0x1000050f8    ;; CALL:fn:1000050f8
1000037ec:     	mov	x0, x20
1000037f0:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
1000037f4:     	b	0x100003808
1000037f8:     	mov	x0, x20
1000037fc:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
100003800:     	movi.2d	v0, #0000000000000000
100003804:     	stp	q0, q0, [x29, #-0x90]
100003808:     	mov	x0, x20
10000380c:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
100003810:     	ldur	x8, [x29, #-0x78]
100003814:     	cbz	x8, 0x100003ac8
100003818:     	sub	x0, x29, #0x90
10000381c:     	sub	x1, x29, #0x70
100003820:     	bl	0x1000050e8    ;; CALL:fn:1000050e8
100003824:     	adrp	x3, 0x10419c000
100003828:     	ldr	x3, [x3, #0xf30]
10000382c:     	sub	x0, x29, #0xa0
100003830:     	sub	x1, x29, #0x70
100003834:     	add	x2, x23, #0x8
100003838:     	mov	w4, #0x7                ; =7
10000383c:     	bl	0x1035de03c    ;; CALL:stub:_swift_dynamicCast
100003840:     	ldp	x0, x20, [x29, #-0xa0]
100003844:     	mov	x1, x20
100003848:     	bl	0x1035d73d0    ;; CALL:stub:_$sSS10FoundationE19_bridgeToObjectiveCSo8NSStringCyF
10000384c:     	mov	x22, x0
100003850:     	mov	x0, x20
100003854:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
100003858:     	adrp	x8, 0x104651000
10000385c:     	ldr	x3, [x8, #0x2a0]
100003860:     	mov	x0, x21
100003864:     	mov	x2, x22
100003868:     	mov	x4, #0x0                ; =0
10000386c:     	bl	0x1035f4540    ;; CALL:objc:loadNibNamed:owner:topLevelObjects:
100003870:     	mov	x0, x22
100003874:     	bl	0x1035dd7cc    ;; CALL:stub:_objc_release
100003878:     	ldr	x8, [x19]
10000387c:     	ldr	x9, [x25]
100003880:     	and	x8, x9, x8
100003884:     	ldr	x8, [x8, #0x3d0]
100003888:     	mov	x20, x19
10000388c:     	blr	x8
100003890:     	mov	x0, x19
100003894:     	bl	0x1035dd7cc    ;; CALL:stub:_objc_release
100003898:     	sub	sp, x29, #0x50
10000389c:     	ldp	x29, x30, [sp, #0x50]
1000038a0:     	ldp	x20, x19, [sp, #0x40]
1000038a4:     	ldp	x22, x21, [sp, #0x30]
1000038a8:     	ldp	x24, x23, [sp, #0x20]
1000038ac:     	ldp	x26, x25, [sp, #0x10]
1000038b0:     	ldp	x28, x27, [sp], #0x60
1000038b4:     	ret
1000038b8:     	cmp	w8, #0x1
1000038bc:     	b.ne	0x100003aa4
1000038c0:     	mov	w0, #0x0                ; =0
1000038c4:     	bl	0x1035dcff8    ;; CALL:stub:_exit
1000038c8:     	bl	0x1035dbe94    ;; CALL:stub:_NSTemporaryDirectory
1000038cc:     	mov	x29, x29
1000038d0:     	bl	0x1035dd7fc    ;; CALL:stub:_objc_retainAutoreleasedReturnValue
1000038d4:     	mov	x20, x0
1000038d8:     	bl	0x1035d7400    ;; CALL:stub:_$sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ
1000038dc:     	mov	x24, x0
1000038e0:     	mov	x25, x1
1000038e4:     	mov	x0, x20
1000038e8:     	bl	0x1035dd7cc    ;; CALL:stub:_objc_release
1000038ec:     	mov	w27, #0x1               ; =1
1000038f0:     	mov	x8, x23
1000038f4:     	mov	x0, x24
1000038f8:     	mov	x1, x25
1000038fc:     	mov	w2, #0x1                ; =1
100003900:     	bl	0x1035d28dc    ;; CALL:stub:_$s10Foundation3URLV15fileURLWithPath11isDirectoryACSSh_SbtcfC
100003904:     	mov	x0, x25
100003908:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
10000390c:     	adrp	x8, 0x1044ac000
100003910:     	ldr	x0, [x8, #0xc18]    ;; CLS:NSProcessInfo
100003914:     	bl	0x1035dd670    ;; CALL:stub:_objc_allocWithZone
100003918:     	bl	0x1035ee6a0    ;; CALL:objc:init
10000391c:     	mov	x20, x0
100003920:     	bl	0x1035ed000    ;; CALL:objc:globallyUniqueString
100003924:     	mov	x29, x29
100003928:     	bl	0x1035dd7fc    ;; CALL:stub:_objc_retainAutoreleasedReturnValue
10000392c:     	mov	x24, x0
100003930:     	mov	x0, x20
100003934:     	bl	0x1035dd7cc    ;; CALL:stub:_objc_release
100003938:     	mov	x0, x24
10000393c:     	bl	0x1035d7400    ;; CALL:stub:_$sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ
100003940:     	mov	x20, x0
100003944:     	mov	x25, x1
100003948:     	mov	x0, x24
10000394c:     	bl	0x1035dd7cc    ;; CALL:stub:_objc_release
100003950:     	mov	x8, x22
100003954:     	mov	x0, x20
100003958:     	mov	x1, x25
10000395c:     	mov	w2, #0x1                ; =1
100003960:     	mov	x20, x23
100003964:     	bl	0x1035d2954    ;; CALL:stub:_$s10Foundation3URLV22appendingPathComponent_11isDirectoryACSS_SbtF
100003968:     	mov	x0, x25
10000396c:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
100003970:     	ldr	x25, [x26, #0x8]
100003974:     	mov	x0, x23
100003978:     	mov	x1, x21
10000397c:     	blr	x25
100003980:     	adrp	x0, 0x1044ee000
100003984:     	add	x0, x0, #0x340
100003988:     	adrp	x1, 0x103644000
10000398c:     	add	x1, x1, #0x860
100003990:     	bl	0x100005134    ;; CALL:fn:100005134
100003994:     	mov	w1, #0x40               ; =64
100003998:     	mov	w2, #0x7                ; =7
10000399c:     	bl	0x1035ddeb0    ;; CALL:stub:_swift_allocObject
1000039a0:     	mov	x23, x0
1000039a4:     	adrp	x8, 0x103644000
1000039a8:     	ldr	q0, [x8, #0x850]    ;; Q:1e-323,2e-323 @0x103644850
1000039ac:     	str	q0, [x0, #0x10]
1000039b0:     	bl	0x1035d9848    ;; CALL:stub:_$ss11CommandLineO9argumentsSaySSGvgZ
1000039b4:     	ldr	x8, [x0, #0x10]
1000039b8:     	cbz	x8, 0x100003acc
1000039bc:     	mov	x20, x0
1000039c0:     	ldp	x26, x24, [x0, #0x20]
1000039c4:     	mov	x0, x24
1000039c8:     	bl	0x1035ddf58    ;; CALL:stub:_swift_bridgeObjectRetain
1000039cc:     	mov	x0, x20
1000039d0:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
1000039d4:     	adrp	x8, 0x103949000
1000039d8:     	add	x8, x8, #0x380    ;; CSTR:--use-mock-keychain
1000039dc:     	stp	x26, x24, [x23, #0x20]
1000039e0:     	sub	x8, x8, #0x20
1000039e4:     	orr	x8, x8, #0x8000000000000000
1000039e8:     	mov	x9, #0x13               ; =19
1000039ec:     	movk	x9, #0xd000, lsl #48
1000039f0:     	stp	x9, x8, [x23, #0x30]
1000039f4:     	bl	0x100d98dd8    ;; CALL:fn:100d98dd8
1000039f8:     	ldp	x20, x24, [x0]
1000039fc:     	ldr	x8, [x19]
100003a00:     	adrp	x9, 0x10419f000
100003a04:     	ldr	x9, [x9, #0xa18]
100003a08:     	ldr	x9, [x9]
100003a0c:     	and	x8, x9, x8
100003a10:     	ldr	x26, [x8, #0x3b8]
100003a14:     	mov	x0, x24
100003a18:     	bl	0x1035ddf58    ;; CALL:stub:_swift_bridgeObjectRetain
100003a1c:     	stp	xzr, xzr, [sp, #-0x20]!
100003a20:     	strh	w27, [sp, #0x10]
100003a24:     	mov	x0, x22
100003a28:     	mov	x1, x23
100003a2c:     	mov	x2, #0x0                ; =0
100003a30:     	mov	w3, #0x1                ; =1
100003a34:     	mov	x4, #0x0                ; =0
100003a38:     	mov	w5, #0x0                ; =0
100003a3c:     	mov	x6, x20
100003a40:     	mov	x7, x24
100003a44:     	mov	x20, x19
100003a48:     	blr	x26
100003a4c:     	add	sp, sp, #0x20
100003a50:     	and	w19, w2, #0xff
100003a54:     	mov	x0, x23
100003a58:     	bl	0x1035de3a8    ;; CALL:stub:_swift_release
100003a5c:     	mov	x0, x24
100003a60:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
100003a64:     	mov	x0, x22
100003a68:     	mov	x1, x21
100003a6c:     	blr	x25
100003a70:     	cbnz	w19, 0x100003ad4
100003a74:     	adrp	x8, 0x1044ac000
100003a78:     	ldr	x0, [x8, #0xc20]    ;; CLS:NSApplication
100003a7c:     	bl	0x1035dd7b4    ;; CALL:stub:_objc_opt_self
100003a80:     	bl	0x1036074c0    ;; CALL:objc:sharedApplication
100003a84:     	mov	x29, x29
100003a88:     	bl	0x1035dd7fc    ;; CALL:stub:_objc_retainAutoreleasedReturnValue
100003a8c:     	mov	x19, x0
100003a90:     	bl	0x1035fb8a0    ;; CALL:objc:run
100003a94:     	mov	x0, x19
100003a98:     	bl	0x1035dd7cc    ;; CALL:stub:_objc_release
100003a9c:     	mov	w0, #0x0                ; =0
100003aa0:     	bl	0x1035dcff8    ;; CALL:stub:_exit
100003aa4:     	mov	x8, #-0x80000000        ; =-2147483648
100003aa8:     	cmp	x20, x8
100003aac:     	b.lt	0x100003ad0
100003ab0:     	mov	w8, #0x7fffffff         ; =2147483647
100003ab4:     	cmp	x20, x8
100003ab8:     	b.gt	0x100003ad8
100003abc:     	mov	x0, x20
100003ac0:     	bl	0x1035dcff8    ;; CALL:stub:_exit
100003ac4:     	brk	#0x1
100003ac8:     	brk	#0x1
100003acc:     	brk	#0x1
100003ad0:     	brk	#0x1
100003ad4:     	brk	#0x1
100003ad8:     	brk	#0x1
