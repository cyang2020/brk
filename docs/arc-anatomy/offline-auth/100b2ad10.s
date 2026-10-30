==== function 0x100b2ad10 (size 0x40)
100b2ad10:     	adrp	x8, 0x104538000
100b2ad14:     	ldr	x8, [x8, #0xab0]
100b2ad18:     	cmn	x8, #0x1
100b2ad1c:     	b.ne	0x100b2ad2c
100b2ad20:     	adrp	x0, 0x104653000
100b2ad24:     	add	x0, x0, #0xf8
100b2ad28:     	ret
100b2ad2c:     	stp	x29, x30, [sp, #-0x10]!
100b2ad30:     	mov	x29, sp
100b2ad34:     	adrp	x0, 0x104538000
100b2ad38:     	add	x0, x0, #0xab0
100b2ad3c:     	adrp	x1, 0x100b2a000
100b2ad40:     	add	x1, x1, #0xce8
100b2ad44:     	bl	0x1035de348    ;; CALL:stub:_swift_once
100b2ad48:     	ldp	x29, x30, [sp], #0x10
100b2ad4c:     	b	0x100b2ad20
