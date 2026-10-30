==== function 0x1007e59f8 (size 0x134)
1007e59f8:     	sub	sp, sp, #0x50
1007e59fc:     	stp	x24, x23, [sp, #0x10]
1007e5a00:     	stp	x22, x21, [sp, #0x20]
1007e5a04:     	stp	x20, x19, [sp, #0x30]
1007e5a08:     	stp	x29, x30, [sp, #0x40]
1007e5a0c:     	add	x29, sp, #0x40
1007e5a10:     	mov	x22, x2
1007e5a14:     	stp	x0, x1, [sp]
1007e5a18:     	mov	x0, x1
1007e5a1c:     	bl	0x1035ddf58    ;; CALL:stub:_swift_bridgeObjectRetain
1007e5a20:     	mov	x20, sp
1007e5a24:     	mov	w0, #0x3d               ; =61
1007e5a28:     	mov	x1, #-0x1f00000000000000 ; =-2233785415175766016    ;; STR:=
1007e5a2c:     	bl	0x1035d7730    ;; CALL:stub:_$sSS6appendyySSF
1007e5a30:     	ldr	x19, [sp, #0x8]
1007e5a34:     	ldr	x23, [x22, #0x10]
1007e5a38:     	cbz	x23, 0x1007e5b00
1007e5a3c:     	ldr	x21, [sp]
1007e5a40:     	add	x24, x22, #0x28
1007e5a44:     	ldp	x22, x20, [x24, #-0x8]
1007e5a48:     	mov	x0, x20
1007e5a4c:     	bl	0x1035ddf58    ;; CALL:stub:_swift_bridgeObjectRetain
1007e5a50:     	mov	x0, x21
1007e5a54:     	mov	x1, x19
1007e5a58:     	mov	x2, x22
1007e5a5c:     	mov	x3, x20
1007e5a60:     	bl	0x1035d7844    ;; CALL:stub:_$sSS9hasPrefixySbSSF
1007e5a64:     	tbnz	w0, #0x0, 0x1007e5a80
1007e5a68:     	add	x24, x24, #0x10
1007e5a6c:     	mov	x0, x20
1007e5a70:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
1007e5a74:     	subs	x23, x23, #0x1
1007e5a78:     	b.ne	0x1007e5a44
1007e5a7c:     	b	0x1007e5b00
1007e5a80:     	mov	x0, x21
1007e5a84:     	mov	x1, x19
1007e5a88:     	bl	0x1035d76b8    ;; CALL:stub:_$sSS5countSivg
1007e5a8c:     	mov	x21, x0
1007e5a90:     	mov	x0, x19
1007e5a94:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
1007e5a98:     	mov	x0, x21
1007e5a9c:     	mov	x1, x22
1007e5aa0:     	mov	x2, x20
1007e5aa4:     	bl	0x1008096bc    ;; CALL:fn:1008096bc
1007e5aa8:     	mov	x19, x0
1007e5aac:     	mov	x21, x1
1007e5ab0:     	mov	x22, x2
1007e5ab4:     	mov	x23, x3
1007e5ab8:     	mov	x0, x20
1007e5abc:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
1007e5ac0:     	mov	x0, x19
1007e5ac4:     	mov	x1, x21
1007e5ac8:     	mov	x2, x22
1007e5acc:     	mov	x3, x23
1007e5ad0:     	bl	0x1035d7604    ;; CALL:stub:_$sSS14_fromSubstringySSSshFZ
1007e5ad4:     	mov	x20, x0
1007e5ad8:     	mov	x19, x1
1007e5adc:     	mov	x0, x23
1007e5ae0:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
1007e5ae4:     	and	x8, x20, #0xffffffffffff
1007e5ae8:     	ubfx	x9, x19, #56, #4
1007e5aec:     	tst	x19, #0x2000000000000000
1007e5af0:     	csel	x8, x8, x9, eq
1007e5af4:     	cbz	x8, 0x1007e5b00
1007e5af8:     	mov	x0, x20
1007e5afc:     	b	0x1007e5b10
1007e5b00:     	mov	x0, x19
1007e5b04:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
1007e5b08:     	mov	x0, #0x0                ; =0
1007e5b0c:     	mov	x19, #0x0               ; =0
1007e5b10:     	mov	x1, x19
1007e5b14:     	ldp	x29, x30, [sp, #0x40]
1007e5b18:     	ldp	x20, x19, [sp, #0x30]
1007e5b1c:     	ldp	x22, x21, [sp, #0x20]
1007e5b20:     	ldp	x24, x23, [sp, #0x10]
1007e5b24:     	add	sp, sp, #0x50
1007e5b28:     	ret
