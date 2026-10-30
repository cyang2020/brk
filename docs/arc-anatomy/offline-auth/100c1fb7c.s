==== function 0x100c1fb7c (size 0xe0)
100c1fb7c:     	stp	x24, x23, [sp, #-0x40]!
100c1fb80:     	stp	x22, x21, [sp, #0x10]
100c1fb84:     	stp	x20, x19, [sp, #0x20]
100c1fb88:     	stp	x29, x30, [sp, #0x30]
100c1fb8c:     	add	x29, sp, #0x30
100c1fb90:     	mov	x19, x1
100c1fb94:     	mov	x20, x0
100c1fb98:     	mov	x21, x8
100c1fb9c:     	adrp	x8, 0x103983000
100c1fba0:     	add	x8, x8, #0x490    ;; CSTR:FAKE_USER_ID_01234567890
100c1fba4:     	sub	x8, x8, #0x20
100c1fba8:     	orr	x23, x8, #0x8000000000000000
100c1fbac:     	mov	x0, #0x0                ; =0
100c1fbb0:     	bl	0x100d64960    ;; CALL:meta:BaseModels.User
100c1fbb4:     	mov	x22, x0
100c1fbb8:     	ldrsw	x8, [x0, #0x1c]
100c1fbbc:     	adrp	x0, 0x103983000
100c1fbc0:     	add	x0, x0, #0x4a9    ;; CSTR:about:blank
100c1fbc4:     	add	x8, x21, x8
100c1fbc8:     	mov	w1, #0xb                ; =11
100c1fbcc:     	mov	w2, #0x2                ; =2
100c1fbd0:     	bl	0x10081bedc    ;; CALL:fn:10081bedc
100c1fbd4:     	ldrsw	x8, [x22, #0x20]
100c1fbd8:     	add	x8, x21, x8
100c1fbdc:     	bl	0x1035d2d80    ;; CALL:stub:_$s10Foundation4DateVACycfC
100c1fbe0:     	mov	x8, #0x18               ; =24
100c1fbe4:     	movk	x8, #0xd000, lsl #48
100c1fbe8:     	stp	x8, x23, [x21]
100c1fbec:     	mov	x8, #0x6554             ; =25940
100c1fbf0:     	movk	x8, #0x7473, lsl #16
100c1fbf4:     	movk	x8, #0x5520, lsl #32
100c1fbf8:     	movk	x8, #0x6573, lsl #48
100c1fbfc:     	mov	x9, #0x72               ; =114
100c1fc00:     	movk	x9, #0xe900, lsl #48    ;; STR:Test User
100c1fc04:     	stp	x8, x9, [x21, #0x10]
100c1fc08:     	adrp	x8, 0x1036d9000
100c1fc0c:     	ldr	q0, [x8, #0xa00]    ;; Q:2.0663389076093375e+161,-3.919106648550025e+202 @0x1036d9a00
100c1fc10:     	str	q0, [x21, #0x20]
100c1fc14:     	mov	x0, #0x0                ; =0
100c1fc18:     	bl	0x100c1ef74    ;; CALL:meta:BaseModels.AuthSession
100c1fc1c:     	ldrsw	x8, [x0, #0x14]
100c1fc20:     	mov	w9, #0x1                ; =1
100c1fc24:     	strb	w9, [x21, x8]
100c1fc28:     	ldrsw	x10, [x0, #0x18]
100c1fc2c:     	strb	w9, [x21, x10]
100c1fc30:     	ldrsw	x9, [x0, #0x1c]
100c1fc34:     	add	x9, x21, x9
100c1fc38:     	movi.2d	v0, #0000000000000000
100c1fc3c:     	stp	q0, q0, [x9]
100c1fc40:     	strb	w20, [x21, x10]
100c1fc44:     	strb	w19, [x21, x8]
100c1fc48:     	ldp	x29, x30, [sp, #0x30]
100c1fc4c:     	ldp	x20, x19, [sp, #0x20]
100c1fc50:     	ldp	x22, x21, [sp, #0x10]
100c1fc54:     	ldp	x24, x23, [sp], #0x40
100c1fc58:     	ret
