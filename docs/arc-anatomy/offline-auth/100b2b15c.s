==== function 0x100b2b15c (size 0x1a8)
100b2b15c:     	sub	sp, sp, #0x50
100b2b160:     	stp	x24, x23, [sp, #0x10]
100b2b164:     	stp	x22, x21, [sp, #0x20]
100b2b168:     	stp	x20, x19, [sp, #0x30]
100b2b16c:     	stp	x29, x30, [sp, #0x40]
100b2b170:     	add	x29, sp, #0x40
100b2b174:     	adrp	x8, 0x104538000
100b2b178:     	ldr	x8, [x8, #0xab0]
100b2b17c:     	cmn	x8, #0x1
100b2b180:     	b.ne	0x100b2b28c
100b2b184:     	adrp	x8, 0x104653000
100b2b188:     	ldrb	w8, [x8, #0xf8]
100b2b18c:     	cmp	w8, #0x1
100b2b190:     	b.ne	0x100b2b264
100b2b194:     	adrp	x8, 0x104538000
100b2b198:     	ldr	x8, [x8, #0xad0]
100b2b19c:     	cmn	x8, #0x1
100b2b1a0:     	b.ne	0x100b2b2a4
100b2b1a4:     	adrp	x8, 0x104653000
100b2b1a8:     	add	x8, x8, #0x100
100b2b1ac:     	ldp	x21, x19, [x8]
100b2b1b0:     	adrp	x8, 0x10419f000
100b2b1b4:     	ldr	x8, [x8, #0x738]
100b2b1b8:     	str	x8, [sp, #0x8]
100b2b1bc:     	mov	x0, x19
100b2b1c0:     	bl	0x1035ddf58    ;; CALL:stub:_swift_bridgeObjectRetain
100b2b1c4:     	add	x20, sp, #0x8
100b2b1c8:     	mov	w0, #0x0                ; =0
100b2b1cc:     	mov	w1, #0x2                ; =2
100b2b1d0:     	mov	w2, #0x0                ; =0
100b2b1d4:     	bl	0x100b2b98c    ;; CALL:fn:100b2b98c
100b2b1d8:     	ldr	x20, [sp, #0x8]
100b2b1dc:     	ldp	x23, x8, [x20, #0x10]
100b2b1e0:     	lsr	x9, x8, #1
100b2b1e4:     	add	x22, x23, #0x1
100b2b1e8:     	cmp	x9, x23
100b2b1ec:     	b.ls	0x100b2b2bc
100b2b1f0:     	str	x22, [x20, #0x10]
100b2b1f4:     	add	x10, x20, x23, lsl #4
100b2b1f8:     	mov	x11, #0x6973            ; =26995
100b2b1fc:     	movk	x11, #0x6e67, lsl #16
100b2b200:     	movk	x11, #0x7055, lsl #32
100b2b204:     	mov	x24, #-0x1a00000000000000 ; =-1873497444986126336    ;; STR:signUp
100b2b208:     	stp	x11, x24, [x10, #0x20]
100b2b20c:     	add	x23, x23, #0x2
100b2b210:     	cmp	x9, x22
100b2b214:     	b.ls	0x100b2b2e4
100b2b218:     	str	x23, [x20, #0x10]
100b2b21c:     	add	x8, x20, x22, lsl #4
100b2b220:     	mov	x9, #0x6973             ; =26995
100b2b224:     	movk	x9, #0x6e67, lsl #16
100b2b228:     	movk	x9, #0x6e49, lsl #32
100b2b22c:     	stp	x9, x24, [x8, #0x20]
100b2b230:     	cbz	x19, 0x100b2b25c
100b2b234:     	mov	x0, x21
100b2b238:     	mov	x1, x19
100b2b23c:     	mov	x2, x20
100b2b240:     	bl	0x100313b58    ;; CALL:fn:100313b58
100b2b244:     	mov	x21, x0
100b2b248:     	mov	x0, x20
100b2b24c:     	bl	0x1035de3a8    ;; CALL:stub:_swift_release
100b2b250:     	mov	x0, x19
100b2b254:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
100b2b258:     	b	0x100b2b268
100b2b25c:     	mov	x0, x20
100b2b260:     	bl	0x1035de3a8    ;; CALL:stub:_swift_release
100b2b264:     	mov	w21, #0x0               ; =0
100b2b268:     	and	w8, w21, #0x1
100b2b26c:     	adrp	x9, 0x104653000
100b2b270:     	strb	w8, [x9, #0x110]
100b2b274:     	ldp	x29, x30, [sp, #0x40]
100b2b278:     	ldp	x20, x19, [sp, #0x30]
100b2b27c:     	ldp	x22, x21, [sp, #0x20]
100b2b280:     	ldp	x24, x23, [sp, #0x10]
100b2b284:     	add	sp, sp, #0x50
100b2b288:     	ret
100b2b28c:     	adrp	x0, 0x104538000
100b2b290:     	add	x0, x0, #0xab0
100b2b294:     	adrp	x1, 0x100b2a000
100b2b298:     	add	x1, x1, #0xce8
100b2b29c:     	bl	0x1035de348    ;; CALL:stub:_swift_once
100b2b2a0:     	b	0x100b2b184
100b2b2a4:     	adrp	x0, 0x104538000
100b2b2a8:     	add	x0, x0, #0xad0
100b2b2ac:     	adrp	x1, 0x100b2b000
100b2b2b0:     	add	x1, x1, #0x2c
100b2b2b4:     	bl	0x1035de348    ;; CALL:stub:_swift_once
100b2b2b8:     	b	0x100b2b1a4
100b2b2bc:     	cmp	x8, #0x1
100b2b2c0:     	cset	w0, hi
100b2b2c4:     	add	x20, sp, #0x8
100b2b2c8:     	mov	x1, x22
100b2b2cc:     	mov	w2, #0x1                ; =1
100b2b2d0:     	bl	0x100b2b98c    ;; CALL:fn:100b2b98c
100b2b2d4:     	ldr	x20, [sp, #0x8]
100b2b2d8:     	ldr	x8, [x20, #0x18]
100b2b2dc:     	lsr	x9, x8, #1
100b2b2e0:     	b	0x100b2b1f0
100b2b2e4:     	cmp	x8, #0x1
100b2b2e8:     	cset	w0, hi
100b2b2ec:     	add	x20, sp, #0x8
100b2b2f0:     	mov	x1, x23
100b2b2f4:     	mov	w2, #0x1                ; =1
100b2b2f8:     	bl	0x100b2b98c    ;; CALL:fn:100b2b98c
100b2b2fc:     	ldr	x20, [sp, #0x8]
100b2b300:     	b	0x100b2b218
