==== function 0x100d865b4 (size 0x9c)
100d865b4:     	stp	x22, x21, [sp, #-0x30]!
100d865b8:     	stp	x20, x19, [sp, #0x10]
100d865bc:     	stp	x29, x30, [sp, #0x20]
100d865c0:     	add	x29, sp, #0x20
100d865c4:     	bl	0x1007e57f8    ;; CALL:fn:1007e57f8
100d865c8:     	ldr	x19, [x0, #0x8]
100d865cc:     	adrp	x22, 0x1044ac000
100d865d0:     	cbz	x19, 0x100d86620
100d865d4:     	ldr	x20, [x0]
100d865d8:     	ldr	x0, [x22, #0xc88]    ;; CLS:NSUserDefaults
100d865dc:     	bl	0x1035dd670    ;; CALL:stub:_objc_allocWithZone
100d865e0:     	mov	x21, x0
100d865e4:     	mov	x0, x19
100d865e8:     	bl	0x1035ddf58    ;; CALL:stub:_swift_bridgeObjectRetain
100d865ec:     	mov	x0, x20
100d865f0:     	mov	x1, x19
100d865f4:     	bl	0x1035d73d0    ;; CALL:stub:_$sSS10FoundationE19_bridgeToObjectiveCSo8NSStringCyF
100d865f8:     	mov	x20, x0
100d865fc:     	mov	x0, x19
100d86600:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
100d86604:     	mov	x0, x21
100d86608:     	mov	x2, x20
100d8660c:     	bl	0x1035f0cc0    ;; CALL:objc:initWithSuiteName:
100d86610:     	mov	x19, x0
100d86614:     	mov	x0, x20
100d86618:     	bl	0x1035dd7cc    ;; CALL:stub:_objc_release
100d8661c:     	cbnz	x19, 0x100d86638
100d86620:     	ldr	x0, [x22, #0xc88]    ;; CLS:NSUserDefaults
100d86624:     	bl	0x1035dd7b4    ;; CALL:stub:_objc_opt_self
100d86628:     	bl	0x103608240    ;; CALL:objc:standardUserDefaults
100d8662c:     	mov	x29, x29
100d86630:     	bl	0x1035dd7fc    ;; CALL:stub:_objc_retainAutoreleasedReturnValue
100d86634:     	mov	x19, x0
100d86638:     	adrp	x8, 0x10465d000
100d8663c:     	str	x19, [x8, #0x148]
100d86640:     	ldp	x29, x30, [sp, #0x20]
100d86644:     	ldp	x20, x19, [sp, #0x10]
100d86648:     	ldp	x22, x21, [sp], #0x30
100d8664c:     	ret
