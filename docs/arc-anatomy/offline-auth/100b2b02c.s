==== function 0x100b2b02c (size 0xf0)
100b2b02c:     	stp	x22, x21, [sp, #-0x30]!
100b2b030:     	stp	x20, x19, [sp, #0x10]
100b2b034:     	stp	x29, x30, [sp, #0x20]
100b2b038:     	add	x29, sp, #0x20
100b2b03c:     	adrp	x8, 0x1044ac000
100b2b040:     	ldr	x0, [x8, #0xc18]    ;; CLS:NSProcessInfo
100b2b044:     	bl	0x1035dd7b4    ;; CALL:stub:_objc_opt_self
100b2b048:     	bl	0x1035f88c0    ;; CALL:objc:processInfo
100b2b04c:     	mov	x29, x29
100b2b050:     	bl	0x1035dd7fc    ;; CALL:stub:_objc_retainAutoreleasedReturnValue
100b2b054:     	mov	x19, x0
100b2b058:     	bl	0x1035ea040    ;; CALL:objc:environment
100b2b05c:     	mov	x29, x29
100b2b060:     	bl	0x1035dd7fc    ;; CALL:stub:_objc_retainAutoreleasedReturnValue
100b2b064:     	mov	x21, x0
100b2b068:     	mov	x0, x19
100b2b06c:     	bl	0x1035dd7cc    ;; CALL:stub:_objc_release
100b2b070:     	adrp	x1, 0x10419c000
100b2b074:     	ldr	x1, [x1, #0xf30]
100b2b078:     	adrp	x3, 0x10419c000
100b2b07c:     	ldr	x3, [x3, #0xf40]
100b2b080:     	mov	x0, x21
100b2b084:     	mov	x2, x1
100b2b088:     	bl	0x1035d6e18    ;; CALL:stub:_$sSD10FoundationE36_unconditionallyBridgeFromObjectiveCySDyxq_GSo12NSDictionaryCSgFZ
100b2b08c:     	mov	x20, x0
100b2b090:     	mov	x0, x21
100b2b094:     	bl	0x1035dd7cc    ;; CALL:stub:_objc_release
100b2b098:     	ldr	x8, [x20, #0x10]
100b2b09c:     	cbz	x8, 0x100b2b0e0
100b2b0a0:     	adrp	x8, 0x10397d000
100b2b0a4:     	add	x8, x8, #0x590    ;; CSTR:ARC_AUTH_UI_TEST_STARTING_SCREEN
100b2b0a8:     	sub	x19, x8, #0x20
100b2b0ac:     	mov	x0, x20
100b2b0b0:     	bl	0x1035ddf58    ;; CALL:stub:_swift_bridgeObjectRetain
100b2b0b4:     	orr	x1, x19, #0x8000000000000000
100b2b0b8:     	mov	x0, #0x20               ; =32
100b2b0bc:     	movk	x0, #0xd000, lsl #48
100b2b0c0:     	bl	0x100004f58    ;; CALL:fn:100004f58
100b2b0c4:     	tbz	w1, #0x0, 0x100b2b0ec
100b2b0c8:     	ldr	x8, [x20, #0x38]
100b2b0cc:     	add	x8, x8, x0, lsl #4
100b2b0d0:     	ldp	x21, x19, [x8]
100b2b0d4:     	mov	x0, x19
100b2b0d8:     	bl	0x1035ddf58    ;; CALL:stub:_swift_bridgeObjectRetain
100b2b0dc:     	b	0x100b2b0f4
100b2b0e0:     	mov	x21, #0x0               ; =0
100b2b0e4:     	mov	x19, #0x0               ; =0
100b2b0e8:     	b	0x100b2b0fc
100b2b0ec:     	mov	x21, #0x0               ; =0
100b2b0f0:     	mov	x19, #0x0               ; =0
100b2b0f4:     	mov	x0, x20
100b2b0f8:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
100b2b0fc:     	adrp	x8, 0x104653000
100b2b100:     	add	x8, x8, #0x100
100b2b104:     	stp	x21, x19, [x8]
100b2b108:     	mov	x0, x20
100b2b10c:     	ldp	x29, x30, [sp, #0x20]
100b2b110:     	ldp	x20, x19, [sp, #0x10]
100b2b114:     	ldp	x22, x21, [sp], #0x30
100b2b118:     	b	0x1035ddf40    ;; TAIL:stub:_swift_bridgeObjectRelease
