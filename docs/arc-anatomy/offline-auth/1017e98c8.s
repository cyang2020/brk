==== function 0x1017e98c8 (size 0x198)
1017e98c8:     	stp	x24, x23, [sp, #-0x40]!
1017e98cc:     	stp	x22, x21, [sp, #0x10]
1017e98d0:     	stp	x20, x19, [sp, #0x20]
1017e98d4:     	stp	x29, x30, [sp, #0x30]
1017e98d8:     	add	x29, sp, #0x30
1017e98dc:     	sub	sp, sp, #0x6e0
1017e98e0:     	mov	x19, x8
1017e98e4:     	add	x22, sp, #0x178
1017e98e8:     	mov	w0, #0x1                ; =1
1017e98ec:     	mov	w1, #0x1                ; =1
1017e98f0:     	bl	0x100c1fb7c    ;; CALL:fn:100c1fb7c
1017e98f4:     	mov	x0, #0x0                ; =0
1017e98f8:     	bl	0x100c1ef74    ;; CALL:meta:BaseModels.AuthSession
1017e98fc:     	mov	x3, x0
1017e9900:     	ldur	x8, [x0, #-0x8]
1017e9904:     	ldr	x8, [x8, #0x38]
1017e9908:     	mov	x0, x19
1017e990c:     	mov	w1, #0x0                ; =0
1017e9910:     	mov	w2, #0x1                ; =1
1017e9914:     	blr	x8
1017e9918:     	mov	x0, #0x0                ; =0
1017e991c:     	bl	0x1017e9e48    ;; CALL:meta:AuthFeature.AuthenticationResult
1017e9920:     	mov	x20, x0
1017e9924:     	ldrsw	x21, [x0, #0x18]
1017e9928:     	mov	x0, #0x0                ; =0
1017e992c:     	bl	0x1016faea4    ;; CALL:meta:MembershipCard.MembershipCardConfiguration
1017e9930:     	mov	x3, x0
1017e9934:     	ldur	x8, [x0, #-0x8]
1017e9938:     	ldr	x8, [x8, #0x38]
1017e993c:     	add	x0, x19, x21
1017e9940:     	mov	w1, #0x1                ; =1
1017e9944:     	mov	w2, #0x1                ; =1
1017e9948:     	blr	x8
1017e994c:     	add	x0, sp, #0x2e8
1017e9950:     	bl	0x1004073fc    ;; CALL:fn:1004073fc
1017e9954:     	ldrsw	x23, [x20, #0x1c]
1017e9958:     	add	x0, x22, #0x58
1017e995c:     	add	x1, sp, #0x2e8
1017e9960:     	mov	w2, #0x111              ; =273
1017e9964:     	bl	0x1035dd568    ;; CALL:stub:_memcpy
1017e9968:     	strb	wzr, [sp, #0x178]
1017e996c:     	movi.2d	v0, #0000000000000000
1017e9970:     	stur	q0, [x22, #0x8]
1017e9974:     	stur	q0, [x22, #0x18]
1017e9978:     	stur	q0, [x22, #0x28]
1017e997c:     	adrp	x21, 0x10419f000
1017e9980:     	ldr	x21, [x21, #0x738]
1017e9984:     	stp	xzr, x21, [sp, #0x1b0]
1017e9988:     	stp	xzr, xzr, [sp, #0x1c0]
1017e998c:     	adrp	x1, 0x1045a8000
1017e9990:     	add	x1, x1, #0x100
1017e9994:     	adrp	x2, 0x103762000
1017e9998:     	add	x2, x2, #0xfa0
1017e999c:     	add	x0, x22, #0x58
1017e99a0:     	bl	0x10000733c    ;; CALL:fn:10000733c
1017e99a4:     	add	x0, x22, #0x58
1017e99a8:     	add	x1, sp, #0x2e8
1017e99ac:     	mov	w2, #0x111              ; =273
1017e99b0:     	bl	0x1035dd568    ;; CALL:stub:_memcpy
1017e99b4:     	add	x0, sp, #0x400
1017e99b8:     	add	x1, sp, #0x178
1017e99bc:     	mov	w2, #0x169              ; =361
1017e99c0:     	bl	0x1035dd568    ;; CALL:stub:_memcpy
1017e99c4:     	add	x0, sp, #0x570
1017e99c8:     	add	x1, sp, #0x178
1017e99cc:     	mov	w2, #0x169              ; =361
1017e99d0:     	bl	0x1035dd568    ;; CALL:stub:_memcpy
1017e99d4:     	add	x0, sp, #0x400
1017e99d8:     	add	x1, sp, #0x8
1017e99dc:     	bl	0x1017e87d0    ;; CALL:fn:1017e87d0
1017e99e0:     	add	x0, sp, #0x570
1017e99e4:     	bl	0x1017e880c    ;; CALL:fn:1017e880c
1017e99e8:     	add	x0, sp, #0x178
1017e99ec:     	add	x1, sp, #0x400
1017e99f0:     	mov	w2, #0x169              ; =361
1017e99f4:     	bl	0x1035dd568    ;; CALL:stub:_memcpy
1017e99f8:     	adrp	x0, 0x1045a8000
1017e99fc:     	add	x0, x0, #0x108
1017e9a00:     	adrp	x1, 0x103762000
1017e9a04:     	add	x1, x1, #0xfa8
1017e9a08:     	bl	0x100005134    ;; CALL:fn:100005134
1017e9a0c:     	mov	x22, x0
1017e9a10:     	bl	0x1017ea3ac    ;; CALL:fn:1017ea3ac
1017e9a14:     	mov	x3, x0
1017e9a18:     	add	x8, x19, x23
1017e9a1c:     	add	x0, sp, #0x178
1017e9a20:     	mov	x1, x21
1017e9a24:     	mov	x2, x22
1017e9a28:     	bl	0x1008f9938    ;; CALL:fn:1008f9938
1017e9a2c:     	ldrsw	x8, [x20, #0x14]
1017e9a30:     	strb	wzr, [x19, x8]
1017e9a34:     	ldrsw	x8, [x20, #0x20]
1017e9a38:     	strb	wzr, [x19, x8]
1017e9a3c:     	ldrsw	x8, [x20, #0x24]
1017e9a40:     	mov	w9, #0x18               ; =24
1017e9a44:     	strb	w9, [x19, x8]
1017e9a48:     	add	sp, sp, #0x6e0
1017e9a4c:     	ldp	x29, x30, [sp, #0x30]
1017e9a50:     	ldp	x20, x19, [sp, #0x20]
1017e9a54:     	ldp	x22, x21, [sp, #0x10]
1017e9a58:     	ldp	x24, x23, [sp], #0x40
1017e9a5c:     	ret
