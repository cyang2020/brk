==== function 0x100b2adbc (size 0x90)
100b2adbc:     	stp	x29, x30, [sp, #-0x10]!
100b2adc0:     	mov	x29, sp
100b2adc4:     	adrp	x8, 0x104538000
100b2adc8:     	ldr	x8, [x8, #0xab0]
100b2adcc:     	cmn	x8, #0x1
100b2add0:     	b.ne	0x100b2ae1c
100b2add4:     	adrp	x8, 0x104653000
100b2add8:     	ldrb	w8, [x8, #0xf8]
100b2addc:     	tbnz	w8, #0x0, 0x100b2adec
100b2ade0:     	bl	0x100811720    ;; CALL:fn:100811720
100b2ade4:     	ldrb	w8, [x0]
100b2ade8:     	tbz	w8, #0x0, 0x100b2adf4
100b2adec:     	mov	w8, #0x1                ; =1
100b2adf0:     	b	0x100b2ae0c
100b2adf4:     	adrp	x8, 0x104538000
100b2adf8:     	ldr	x8, [x8, #0xab8]
100b2adfc:     	cmn	x8, #0x1
100b2ae00:     	b.ne	0x100b2ae34
100b2ae04:     	adrp	x8, 0x104653000
100b2ae08:     	ldrb	w8, [x8, #0xf9]
100b2ae0c:     	adrp	x9, 0x104653000
100b2ae10:     	strb	w8, [x9, #0xfa]
100b2ae14:     	ldp	x29, x30, [sp], #0x10
100b2ae18:     	ret
100b2ae1c:     	adrp	x0, 0x104538000
100b2ae20:     	add	x0, x0, #0xab0
100b2ae24:     	adrp	x1, 0x100b2a000
100b2ae28:     	add	x1, x1, #0xce8
100b2ae2c:     	bl	0x1035de348    ;; CALL:stub:_swift_once
100b2ae30:     	b	0x100b2add4
100b2ae34:     	adrp	x0, 0x104538000
100b2ae38:     	add	x0, x0, #0xab8
100b2ae3c:     	adrp	x1, 0x100b2a000
100b2ae40:     	add	x1, x1, #0xd50
100b2ae44:     	bl	0x1035de348    ;; CALL:stub:_swift_once
100b2ae48:     	b	0x100b2ae04
