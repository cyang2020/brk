==== function 0x100b2aeb8 (size 0x134)
100b2aeb8:     	stp	x24, x23, [sp, #-0x40]!
100b2aebc:     	stp	x22, x21, [sp, #0x10]
100b2aec0:     	stp	x20, x19, [sp, #0x20]
100b2aec4:     	stp	x29, x30, [sp, #0x30]
100b2aec8:     	add	x29, sp, #0x30
100b2aecc:     	mov	x19, x3
100b2aed0:     	mov	x20, x2
100b2aed4:     	mov	x22, x1
100b2aed8:     	adrp	x8, 0x1044ac000
100b2aedc:     	ldr	x0, [x8, #0xc18]    ;; CLS:NSProcessInfo
100b2aee0:     	bl	0x1035dd7b4    ;; CALL:stub:_objc_opt_self
100b2aee4:     	bl	0x1035f88c0    ;; CALL:objc:processInfo
100b2aee8:     	mov	x29, x29
100b2aeec:     	bl	0x1035dd7fc    ;; CALL:stub:_objc_retainAutoreleasedReturnValue
100b2aef0:     	mov	x21, x0
100b2aef4:     	bl	0x1035ea040    ;; CALL:objc:environment
100b2aef8:     	mov	x29, x29
100b2aefc:     	bl	0x1035dd7fc    ;; CALL:stub:_objc_retainAutoreleasedReturnValue
100b2af00:     	mov	x23, x0
100b2af04:     	mov	x0, x21
100b2af08:     	bl	0x1035dd7cc    ;; CALL:stub:_objc_release
100b2af0c:     	adrp	x1, 0x10419c000
100b2af10:     	ldr	x1, [x1, #0xf30]
100b2af14:     	adrp	x3, 0x10419c000
100b2af18:     	ldr	x3, [x3, #0xf40]
100b2af1c:     	mov	x0, x23
100b2af20:     	mov	x2, x1
100b2af24:     	bl	0x1035d6e18    ;; CALL:stub:_$sSD10FoundationE36_unconditionallyBridgeFromObjectiveCySDyxq_GSo12NSDictionaryCSgFZ
100b2af28:     	mov	x21, x0
100b2af2c:     	mov	x0, x23
100b2af30:     	bl	0x1035dd7cc    ;; CALL:stub:_objc_release
100b2af34:     	ldr	x8, [x21, #0x10]
100b2af38:     	cbz	x8, 0x100b2afa8
100b2af3c:     	mov	x0, x21
100b2af40:     	bl	0x1035ddf58    ;; CALL:stub:_swift_bridgeObjectRetain
100b2af44:     	mov	x0, x22
100b2af48:     	mov	x1, x20
100b2af4c:     	mov	x20, x21
100b2af50:     	bl	0x100004f58    ;; CALL:fn:100004f58
100b2af54:     	tbz	w1, #0x0, 0x100b2afb0
100b2af58:     	ldr	x8, [x21, #0x38]
100b2af5c:     	add	x8, x8, x0, lsl #4
100b2af60:     	ldp	x22, x20, [x8]
100b2af64:     	mov	x0, x20
100b2af68:     	bl	0x1035ddf58    ;; CALL:stub:_swift_bridgeObjectRetain
100b2af6c:     	mov	x0, x21
100b2af70:     	mov	w1, #0x2                ; =2
100b2af74:     	bl	0x1035ddf4c    ;; CALL:stub:_swift_bridgeObjectRelease_n
100b2af78:     	cmp	x22, #0x31
100b2af7c:     	mov	x8, #-0x1f00000000000000 ; =-2233785415175766016
100b2af80:     	ccmp	x20, x8, #0x0, eq
100b2af84:     	b.eq	0x100b2afc0
100b2af88:     	mov	x0, x22
100b2af8c:     	mov	x1, x20
100b2af90:     	mov	w2, #0x31               ; =49
100b2af94:     	mov	x3, #-0x1f00000000000000 ; =-2233785415175766016    ;; STR:1
100b2af98:     	mov	w4, #0x0                ; =0
100b2af9c:     	bl	0x1035da838    ;; CALL:stub:_$ss27_stringCompareWithSmolCheck__9expectingSbs11_StringGutsV_ADs01_G16ComparisonResultOtF
100b2afa0:     	mov	x22, x0
100b2afa4:     	b	0x100b2afc4
100b2afa8:     	mov	w22, #0x0               ; =0
100b2afac:     	b	0x100b2afc8
100b2afb0:     	mov	x0, x21
100b2afb4:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
100b2afb8:     	mov	w22, #0x0               ; =0
100b2afbc:     	b	0x100b2afc8
100b2afc0:     	mov	w22, #0x1               ; =1
100b2afc4:     	mov	x21, x20
100b2afc8:     	mov	x0, x21
100b2afcc:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
100b2afd0:     	and	w8, w22, #0x1
100b2afd4:     	strb	w8, [x19]
100b2afd8:     	ldp	x29, x30, [sp, #0x30]
100b2afdc:     	ldp	x20, x19, [sp, #0x20]
100b2afe0:     	ldp	x22, x21, [sp, #0x10]
100b2afe4:     	ldp	x24, x23, [sp], #0x40
100b2afe8:     	ret
