==== function 0x102e448d0 (size 0x4fc)
102e448d0:     	sub	sp, sp, #0x1b0
102e448d4:     	stp	x26, x25, [sp, #0x160]
102e448d8:     	stp	x24, x23, [sp, #0x170]
102e448dc:     	stp	x22, x21, [sp, #0x180]
102e448e0:     	stp	x20, x19, [sp, #0x190]
102e448e4:     	stp	x29, x30, [sp, #0x1a0]
102e448e8:     	add	x29, sp, #0x1a0
102e448ec:     	mov	x22, x0
102e448f0:     	bl	0x100b2ae4c    ;; CALL:fn:100b2ae4c
102e448f4:     	ldrb	w8, [x0]
102e448f8:     	tbz	w8, #0x0, 0x102e44904
102e448fc:     	mov	w0, #0x0                ; =0
102e44900:     	b	0x102e44a80
102e44904:     	add	x24, sp, #0x88
102e44908:     	bl	0x100d648c4    ;; CALL:fn:100d648c4
102e4490c:     	ldp	x2, x3, [x0]
102e44910:     	ldp	x19, x21, [x20]
102e44914:     	cmp	x19, x2
102e44918:     	ccmp	x21, x3, #0x0, eq
102e4491c:     	b.eq	0x102e44934
102e44920:     	mov	x0, x19
102e44924:     	mov	x1, x21
102e44928:     	mov	w4, #0x0                ; =0
102e4492c:     	bl	0x1035da838    ;; CALL:stub:_$ss27_stringCompareWithSmolCheck__9expectingSbs11_StringGutsV_ADs01_G16ComparisonResultOtF
102e44930:     	tbz	w0, #0x0, 0x102e44a9c
102e44934:     	adrp	x8, 0x10463d000
102e44938:     	ldr	x8, [x8, #0xf0]
102e4493c:     	cmn	x8, #0x1
102e44940:     	b.ne	0x102e44d84
102e44944:     	adrp	x8, 0x10466b000
102e44948:     	ldr	x22, [x8, #0x910]
102e4494c:     	add	x0, x22, #0x20
102e44950:     	sub	x1, x29, #0xb8
102e44954:     	mov	x2, #0x0                ; =0
102e44958:     	mov	x3, #0x0                ; =0
102e4495c:     	bl	0x1035ddf34    ;; CALL:stub:_swift_beginAccess
102e44960:     	add	x0, x22, #0x20
102e44964:     	sub	x1, x29, #0xa0
102e44968:     	bl	0x100012c10    ;; CALL:fn:100012c10
102e4496c:     	ldp	x19, x21, [x29, #-0x88]
102e44970:     	sub	x0, x29, #0xa0
102e44974:     	mov	x1, x19
102e44978:     	bl	0x100012c54    ;; CALL:fn:100012c54
102e4497c:     	ldr	x8, [x21, #0x70]
102e44980:     	mov	x20, x0
102e44984:     	mov	x0, x19
102e44988:     	mov	x1, x21
102e4498c:     	blr	x8
102e44990:     	and	w19, w0, #0xff
102e44994:     	sub	x0, x29, #0xa0
102e44998:     	bl	0x100012e70    ;; CALL:fn:100012e70
102e4499c:     	cmp	w19, #0x2
102e449a0:     	b.hi	0x102e44a7c
102e449a4:     	adrp	x8, 0x103a35000
102e449a8:     	add	x8, x8, #0xab0    ;; CSTR:SharedAppFeature/AuthSession+UserStatus.swift
102e449ac:     	sub	x8, x8, #0x20
102e449b0:     	orr	x23, x8, #0x8000000000000000
102e449b4:     	adrp	x8, 0x103a35000
102e449b8:     	add	x8, x8, #0xae0    ;; CSTR:userStatus(client:)
102e449bc:     	sub	x8, x8, #0x20
102e449c0:     	orr	x25, x8, #0x8000000000000000
102e449c4:     	add	x0, x22, #0x20
102e449c8:     	add	x1, sp, #0x60
102e449cc:     	bl	0x100012c10    ;; CALL:fn:100012c10
102e449d0:     	ldp	x19, x21, [sp, #0x78]
102e449d4:     	add	x0, sp, #0x60
102e449d8:     	mov	x1, x19
102e449dc:     	bl	0x100012c54    ;; CALL:fn:100012c54
102e449e0:     	mov	x20, x0
102e449e4:     	mov	w8, #0x2                ; =2
102e449e8:     	sturb	w8, [x29, #-0xa0]
102e449ec:     	adrp	x9, 0x103a35000
102e449f0:     	add	x9, x9, #0xb90    ;; CSTR:Cleaning up session because of fake ID
102e449f4:     	sub	x9, x9, #0x20
102e449f8:     	orr	x9, x9, #0x8000000000000000
102e449fc:     	mov	x10, #0x13              ; =19
102e44a00:     	movk	x10, #0xd000, lsl #48
102e44a04:     	add	x11, x10, #0x13
102e44a08:     	stp	x11, x9, [x29, #-0x98]
102e44a0c:     	movi.2d	v0, #0000000000000000
102e44a10:     	stp	q0, q0, [x24, #0x90]
102e44a14:     	add	x12, x10, #0x1a
102e44a18:     	stp	x12, x23, [x29, #-0x68]
102e44a1c:     	stp	x10, x25, [x29, #-0x58]
102e44a20:     	mov	w13, #0x17              ; =23
102e44a24:     	stur	x13, [x29, #-0x48]
102e44a28:     	strb	w8, [sp, #0x88]
102e44a2c:     	stp	x11, x9, [sp, #0x90]
102e44a30:     	stur	q0, [x24, #0x18]
102e44a34:     	stur	q0, [x24, #0x28]
102e44a38:     	stp	x12, x23, [sp, #0xc0]
102e44a3c:     	stp	x10, x25, [sp, #0xd0]
102e44a40:     	str	x13, [sp, #0xe0]
102e44a44:     	sub	x0, x29, #0xa0
102e44a48:     	mov	x1, sp
102e44a4c:     	bl	0x100582d5c    ;; CALL:fn:100582d5c
102e44a50:     	add	x0, sp, #0x88
102e44a54:     	bl	0x100012cf4    ;; CALL:fn:100012cf4
102e44a58:     	ldr	x8, [x21, #0x28]
102e44a5c:     	sub	x0, x29, #0xa0
102e44a60:     	mov	x1, x19
102e44a64:     	mov	x2, x21
102e44a68:     	blr	x8
102e44a6c:     	sub	x0, x29, #0xa0
102e44a70:     	bl	0x100012cf4    ;; CALL:fn:100012cf4
102e44a74:     	add	x0, sp, #0x60
102e44a78:     	bl	0x100012e70    ;; CALL:fn:100012e70
102e44a7c:     	mov	w0, #0x1                ; =1
102e44a80:     	ldp	x29, x30, [sp, #0x1a0]
102e44a84:     	ldp	x20, x19, [sp, #0x190]
102e44a88:     	ldp	x22, x21, [sp, #0x180]
102e44a8c:     	ldp	x24, x23, [sp, #0x170]
102e44a90:     	ldp	x26, x25, [sp, #0x160]
102e44a94:     	add	sp, sp, #0x1b0
102e44a98:     	ret
102e44a9c:     	ldp	x8, x20, [x22, #0x190]
102e44aa0:     	blr	x8
102e44aa4:     	mov	x22, x0
102e44aa8:     	bl	0x1035e6c60    ;; CALL:objc:currentUser
102e44aac:     	mov	x29, x29
102e44ab0:     	bl	0x1035dd7fc    ;; CALL:stub:_objc_retainAutoreleasedReturnValue
102e44ab4:     	mov	x20, x0
102e44ab8:     	mov	x0, x22
102e44abc:     	bl	0x1035dd7cc    ;; CALL:stub:_objc_release
102e44ac0:     	cbz	x20, 0x102e44b18
102e44ac4:     	mov	x0, x20
102e44ac8:     	bl	0x10360afc0    ;; CALL:objc:uid
102e44acc:     	mov	x29, x29
102e44ad0:     	bl	0x1035dd7fc    ;; CALL:stub:_objc_retainAutoreleasedReturnValue
102e44ad4:     	mov	x22, x0
102e44ad8:     	mov	x0, x20
102e44adc:     	bl	0x1035dd7cc    ;; CALL:stub:_objc_release
102e44ae0:     	mov	x0, x22
102e44ae4:     	bl	0x1035d7400    ;; CALL:stub:_$sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ
102e44ae8:     	mov	x23, x0
102e44aec:     	mov	x20, x1
102e44af0:     	mov	x0, x22
102e44af4:     	bl	0x1035dd7cc    ;; CALL:stub:_objc_release
102e44af8:     	cmp	x23, x19
102e44afc:     	b.ne	0x102e44c68
102e44b00:     	cmp	x20, x21
102e44b04:     	b.ne	0x102e44c68
102e44b08:     	mov	x0, x20
102e44b0c:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
102e44b10:     	mov	w0, #0x0                ; =0
102e44b14:     	b	0x102e44a80
102e44b18:     	adrp	x8, 0x10463d000
102e44b1c:     	ldr	x8, [x8, #0xf0]
102e44b20:     	cmn	x8, #0x1
102e44b24:     	b.ne	0x102e44d9c
102e44b28:     	adrp	x8, 0x10466b000
102e44b2c:     	ldr	x22, [x8, #0x910]
102e44b30:     	add	x0, x22, #0x20
102e44b34:     	sub	x1, x29, #0xb8
102e44b38:     	mov	x2, #0x0                ; =0
102e44b3c:     	mov	x3, #0x0                ; =0
102e44b40:     	bl	0x1035ddf34    ;; CALL:stub:_swift_beginAccess
102e44b44:     	add	x0, x22, #0x20
102e44b48:     	sub	x1, x29, #0xa0
102e44b4c:     	bl	0x100012c10    ;; CALL:fn:100012c10
102e44b50:     	ldp	x19, x21, [x29, #-0x88]
102e44b54:     	sub	x0, x29, #0xa0
102e44b58:     	mov	x1, x19
102e44b5c:     	bl	0x100012c54    ;; CALL:fn:100012c54
102e44b60:     	ldr	x8, [x21, #0x70]
102e44b64:     	mov	x20, x0
102e44b68:     	mov	x0, x19
102e44b6c:     	mov	x1, x21
102e44b70:     	blr	x8
102e44b74:     	and	w19, w0, #0xff
102e44b78:     	sub	x0, x29, #0xa0
102e44b7c:     	bl	0x100012e70    ;; CALL:fn:100012e70
102e44b80:     	cmp	w19, #0x4
102e44b84:     	b.hi	0x102e44c60
102e44b88:     	adrp	x8, 0x103a35000
102e44b8c:     	add	x8, x8, #0xab0    ;; CSTR:SharedAppFeature/AuthSession+UserStatus.swift
102e44b90:     	sub	x8, x8, #0x20
102e44b94:     	orr	x23, x8, #0x8000000000000000
102e44b98:     	adrp	x8, 0x103a35000
102e44b9c:     	add	x8, x8, #0xae0    ;; CSTR:userStatus(client:)
102e44ba0:     	sub	x8, x8, #0x20
102e44ba4:     	orr	x25, x8, #0x8000000000000000
102e44ba8:     	add	x0, x22, #0x20
102e44bac:     	add	x1, sp, #0x60
102e44bb0:     	bl	0x100012c10    ;; CALL:fn:100012c10
102e44bb4:     	ldp	x19, x21, [sp, #0x78]
102e44bb8:     	add	x0, sp, #0x60
102e44bbc:     	mov	x1, x19
102e44bc0:     	bl	0x100012c54    ;; CALL:fn:100012c54
102e44bc4:     	mov	x20, x0
102e44bc8:     	mov	w8, #0x4                ; =4
102e44bcc:     	sturb	w8, [x29, #-0xa0]
102e44bd0:     	adrp	x9, 0x103a35000
102e44bd4:     	add	x9, x9, #0xb00    ;; CSTR:Prompt user to sign out current session because Firebase UserID doesn't exist
102e44bd8:     	sub	x9, x9, #0x20
102e44bdc:     	orr	x9, x9, #0x8000000000000000
102e44be0:     	mov	x10, #0x13              ; =19
102e44be4:     	movk	x10, #0xd000, lsl #48
102e44be8:     	add	x11, x10, #0x3a
102e44bec:     	stp	x11, x9, [x29, #-0x98]
102e44bf0:     	movi.2d	v0, #0000000000000000
102e44bf4:     	stp	q0, q0, [x24, #0x90]
102e44bf8:     	add	x12, x10, #0x1a
102e44bfc:     	stp	x12, x23, [x29, #-0x68]
102e44c00:     	stp	x10, x25, [x29, #-0x58]
102e44c04:     	mov	w13, #0x1d              ; =29
102e44c08:     	stur	x13, [x29, #-0x48]
102e44c0c:     	strb	w8, [sp, #0x88]
102e44c10:     	stp	x11, x9, [sp, #0x90]
102e44c14:     	stur	q0, [x24, #0x18]
102e44c18:     	stur	q0, [x24, #0x28]
102e44c1c:     	stp	x12, x23, [sp, #0xc0]
102e44c20:     	stp	x10, x25, [sp, #0xd0]
102e44c24:     	str	x13, [sp, #0xe0]
102e44c28:     	sub	x0, x29, #0xa0
102e44c2c:     	mov	x1, sp
102e44c30:     	bl	0x100582d5c    ;; CALL:fn:100582d5c
102e44c34:     	add	x0, sp, #0x88
102e44c38:     	bl	0x100012cf4    ;; CALL:fn:100012cf4
102e44c3c:     	ldr	x8, [x21, #0x28]
102e44c40:     	sub	x0, x29, #0xa0
102e44c44:     	mov	x1, x19
102e44c48:     	mov	x2, x21
102e44c4c:     	blr	x8
102e44c50:     	sub	x0, x29, #0xa0
102e44c54:     	bl	0x100012cf4    ;; CALL:fn:100012cf4
102e44c58:     	add	x0, sp, #0x60
102e44c5c:     	bl	0x100012e70    ;; CALL:fn:100012e70
102e44c60:     	mov	w0, #0x2                ; =2
102e44c64:     	b	0x102e44a80
102e44c68:     	mov	x0, x23
102e44c6c:     	mov	x1, x20
102e44c70:     	mov	x2, x19
102e44c74:     	mov	x3, x21
102e44c78:     	mov	w4, #0x0                ; =0
102e44c7c:     	bl	0x1035da838    ;; CALL:stub:_$ss27_stringCompareWithSmolCheck__9expectingSbs11_StringGutsV_ADs01_G16ComparisonResultOtF
102e44c80:     	mov	x19, x0
102e44c84:     	mov	x0, x20
102e44c88:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
102e44c8c:     	tbnz	w19, #0x0, 0x102e448fc
102e44c90:     	adrp	x8, 0x10463d000
102e44c94:     	ldr	x8, [x8, #0xf0]
102e44c98:     	cmn	x8, #0x1
102e44c9c:     	b.ne	0x102e44db4
102e44ca0:     	adrp	x8, 0x10466b000
102e44ca4:     	ldr	x22, [x8, #0x910]
102e44ca8:     	add	x0, x22, #0x20
102e44cac:     	sub	x1, x29, #0xb8
102e44cb0:     	mov	x2, #0x0                ; =0
102e44cb4:     	mov	x3, #0x0                ; =0
102e44cb8:     	bl	0x1035ddf34    ;; CALL:stub:_swift_beginAccess
102e44cbc:     	add	x0, x22, #0x20
102e44cc0:     	sub	x1, x29, #0xa0
102e44cc4:     	bl	0x100012c10    ;; CALL:fn:100012c10
102e44cc8:     	ldp	x19, x21, [x29, #-0x88]
102e44ccc:     	sub	x0, x29, #0xa0
102e44cd0:     	mov	x1, x19
102e44cd4:     	bl	0x100012c54    ;; CALL:fn:100012c54
102e44cd8:     	ldr	x8, [x21, #0x70]
102e44cdc:     	mov	x20, x0
102e44ce0:     	mov	x0, x19
102e44ce4:     	mov	x1, x21
102e44ce8:     	blr	x8
102e44cec:     	and	w19, w0, #0xff
102e44cf0:     	sub	x0, x29, #0xa0
102e44cf4:     	bl	0x100012e70    ;; CALL:fn:100012e70
102e44cf8:     	cmp	w19, #0x5
102e44cfc:     	b.hi	0x102e44a7c
102e44d00:     	adrp	x8, 0x103a35000
102e44d04:     	add	x8, x8, #0xab0    ;; CSTR:SharedAppFeature/AuthSession+UserStatus.swift
102e44d08:     	sub	x8, x8, #0x20
102e44d0c:     	orr	x23, x8, #0x8000000000000000
102e44d10:     	adrp	x8, 0x103a35000
102e44d14:     	add	x8, x8, #0xae0    ;; CSTR:userStatus(client:)
102e44d18:     	sub	x8, x8, #0x20
102e44d1c:     	orr	x25, x8, #0x8000000000000000
102e44d20:     	add	x0, x22, #0x20
102e44d24:     	add	x1, sp, #0x60
102e44d28:     	bl	0x100012c10    ;; CALL:fn:100012c10
102e44d2c:     	ldp	x19, x21, [sp, #0x78]
102e44d30:     	add	x0, sp, #0x60
102e44d34:     	mov	x1, x19
102e44d38:     	bl	0x100012c54    ;; CALL:fn:100012c54
102e44d3c:     	mov	x20, x0
102e44d40:     	mov	w8, #0x5                ; =5
102e44d44:     	sturb	w8, [x29, #-0xa0]
102e44d48:     	adrp	x9, 0x103a35000
102e44d4c:     	add	x9, x9, #0xb50    ;; CSTR:Cleaning up session because Firebase UserID doesn't match
102e44d50:     	sub	x9, x9, #0x20
102e44d54:     	orr	x9, x9, #0x8000000000000000
102e44d58:     	mov	x10, #0x13              ; =19
102e44d5c:     	movk	x10, #0xd000, lsl #48
102e44d60:     	add	x11, x10, #0x26
102e44d64:     	stp	x11, x9, [x29, #-0x98]
102e44d68:     	movi.2d	v0, #0000000000000000
102e44d6c:     	stp	q0, q0, [x24, #0x90]
102e44d70:     	add	x12, x10, #0x1a
102e44d74:     	stp	x12, x23, [x29, #-0x68]
102e44d78:     	stp	x10, x25, [x29, #-0x58]
102e44d7c:     	mov	w13, #0x23              ; =35
102e44d80:     	b	0x102e44a24
102e44d84:     	adrp	x0, 0x10463d000
102e44d88:     	add	x0, x0, #0xf0
102e44d8c:     	adrp	x1, 0x102e4f000
102e44d90:     	add	x1, x1, #0xdb8
102e44d94:     	bl	0x1035de348    ;; CALL:stub:_swift_once
102e44d98:     	b	0x102e44944
102e44d9c:     	adrp	x0, 0x10463d000
102e44da0:     	add	x0, x0, #0xf0
102e44da4:     	adrp	x1, 0x102e4f000
102e44da8:     	add	x1, x1, #0xdb8
102e44dac:     	bl	0x1035de348    ;; CALL:stub:_swift_once
102e44db0:     	b	0x102e44b28
102e44db4:     	adrp	x0, 0x10463d000
102e44db8:     	add	x0, x0, #0xf0
102e44dbc:     	adrp	x1, 0x102e4f000
102e44dc0:     	add	x1, x1, #0xdb8
102e44dc4:     	bl	0x1035de348    ;; CALL:stub:_swift_once
102e44dc8:     	b	0x102e44ca0
