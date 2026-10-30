==== function 0x102e00cc8 (size 0x600)
102e00cc8:     	stp	x28, x27, [sp, #-0x60]!
102e00ccc:     	stp	x26, x25, [sp, #0x10]
102e00cd0:     	stp	x24, x23, [sp, #0x20]
102e00cd4:     	stp	x22, x21, [sp, #0x30]
102e00cd8:     	stp	x20, x19, [sp, #0x40]
102e00cdc:     	stp	x29, x30, [sp, #0x50]
102e00ce0:     	add	x29, sp, #0x50
102e00ce4:     	sub	sp, sp, #0x30
102e00ce8:     	mov	x25, x1
102e00cec:     	mov	x28, x0
102e00cf0:     	mov	x0, #0x0                ; =0
102e00cf4:     	bl	0x102de4e8c    ;; CALL:meta:SharedAppFeature.AppAction
102e00cf8:     	mov	x21, x0
102e00cfc:     	ldur	x8, [x0, #-0x8]
102e00d00:     	stur	x8, [x29, #-0x58]
102e00d04:     	ldr	x8, [x8, #0x40]
102e00d08:     	mov	x9, x8
102e00d0c:     	adrp	x16, 0x104197000
102e00d10:     	ldr	x16, [x16, #0x3b0]
102e00d14:     	blr	x16
102e00d18:     	mov	x9, sp
102e00d1c:     	add	x8, x8, #0xf
102e00d20:     	and	x8, x8, #0xfffffffffffffff0
102e00d24:     	sub	x8, x9, x8
102e00d28:     	stur	x8, [x29, #-0x70]
102e00d2c:     	mov	sp, x8
102e00d30:     	adrp	x0, 0x10463c000
102e00d34:     	add	x0, x0, #0x230
102e00d38:     	adrp	x1, 0x103843000
102e00d3c:     	add	x1, x1, #0x778
102e00d40:     	bl	0x100005134    ;; CALL:fn:100005134
102e00d44:     	stur	x0, [x29, #-0x68]
102e00d48:     	ldur	x22, [x0, #-0x8]
102e00d4c:     	ldr	x8, [x22, #0x40]
102e00d50:     	mov	x9, x8
102e00d54:     	adrp	x16, 0x104197000
102e00d58:     	ldr	x16, [x16, #0x3b0]
102e00d5c:     	blr	x16
102e00d60:     	mov	x9, sp
102e00d64:     	add	x10, x8, #0xf
102e00d68:     	and	x12, x10, #0xfffffffffffffff0
102e00d6c:     	sub	x24, x9, x12
102e00d70:     	mov	sp, x24
102e00d74:     	mov	x9, x8
102e00d78:     	adrp	x16, 0x104197000
102e00d7c:     	ldr	x16, [x16, #0x3b0]
102e00d80:     	blr	x16
102e00d84:     	mov	x8, sp
102e00d88:     	sub	x26, x8, x12
102e00d8c:     	mov	sp, x26
102e00d90:     	adrp	x0, 0x10463b000
102e00d94:     	add	x0, x0, #0xd50
102e00d98:     	adrp	x1, 0x103846000
102e00d9c:     	add	x1, x1, #0xc60
102e00da0:     	bl	0x100005134    ;; CALL:fn:100005134
102e00da4:     	ldur	x8, [x0, #-0x8]
102e00da8:     	ldr	x9, [x8, #0x40]
102e00dac:     	add	x8, x9, #0xf
102e00db0:     	and	x8, x8, #0xfffffffffffffff0
102e00db4:     	adrp	x16, 0x104197000
102e00db8:     	ldr	x16, [x16, #0x3b0]
102e00dbc:     	blr	x16
102e00dc0:     	mov	x9, sp
102e00dc4:     	sub	x19, x9, x8
102e00dc8:     	mov	sp, x19
102e00dcc:     	mov	x0, #0x0                ; =0
102e00dd0:     	bl	0x100c1ef74    ;; CALL:meta:BaseModels.AuthSession
102e00dd4:     	mov	x27, x0
102e00dd8:     	ldur	x23, [x0, #-0x8]
102e00ddc:     	ldr	x8, [x23, #0x40]
102e00de0:     	mov	x9, x8
102e00de4:     	adrp	x16, 0x104197000
102e00de8:     	ldr	x16, [x16, #0x3b0]
102e00dec:     	blr	x16
102e00df0:     	mov	x9, sp
102e00df4:     	add	x8, x8, #0xf
102e00df8:     	and	x8, x8, #0xfffffffffffffff0
102e00dfc:     	sub	x8, x9, x8
102e00e00:     	stur	x8, [x29, #-0x60]
102e00e04:     	mov	sp, x8
102e00e08:     	bl	0x100b2ae4c    ;; CALL:fn:100b2ae4c
102e00e0c:     	ldrb	w8, [x0]
102e00e10:     	cmp	w8, #0x1
102e00e14:     	b.ne	0x102e00ed8
102e00e18:     	bl	0x100b2afec    ;; CALL:fn:100b2afec
102e00e1c:     	ldrb	w8, [x0]
102e00e20:     	cmp	w8, #0x1
102e00e24:     	b.ne	0x102e00ed8
102e00e28:     	adrp	x0, 0x10463b000
102e00e2c:     	add	x0, x0, #0xb50
102e00e30:     	adrp	x1, 0x103841000
102e00e34:     	add	x1, x1, #0xbe0
102e00e38:     	bl	0x100005134    ;; CALL:fn:100005134
102e00e3c:     	ldur	x8, [x29, #-0x58]
102e00e40:     	ldr	x22, [x8, #0x48]
102e00e44:     	ldrb	w8, [x8, #0x50]
102e00e48:     	add	x9, x8, #0x20
102e00e4c:     	bic	x19, x9, x8
102e00e50:     	add	x1, x19, x22, lsl #1
102e00e54:     	orr	x2, x8, #0x7
102e00e58:     	bl	0x1035ddeb0    ;; CALL:stub:_swift_allocObject
102e00e5c:     	mov	x27, x0
102e00e60:     	adrp	x8, 0x103644000
102e00e64:     	ldr	q0, [x8, #0x850]    ;; Q:1e-323,2e-323 @0x103644850
102e00e68:     	str	q0, [x0, #0x10]
102e00e6c:     	add	x19, x0, x19
102e00e70:     	mov	x8, x19
102e00e74:     	mov	w0, #0x1                ; =1
102e00e78:     	mov	w1, #0x1                ; =1
102e00e7c:     	bl	0x100c1fb7c    ;; CALL:fn:100c1fb7c
102e00e80:     	mov	x0, #0x0                ; =0
102e00e84:     	bl	0x1017d8d0c    ;; CALL:meta:AuthFeature.AuthFeature.Action
102e00e88:     	mov	x20, x0
102e00e8c:     	mov	x0, x19
102e00e90:     	mov	x1, x20
102e00e94:     	mov	w2, #0x0                ; =0
102e00e98:     	bl	0x1035de42c    ;; CALL:stub:_swift_storeEnumTagMultiPayload
102e00e9c:     	mov	x0, x19
102e00ea0:     	mov	x1, x21
102e00ea4:     	mov	w2, #0x12               ; =18
102e00ea8:     	bl	0x1035de42c    ;; CALL:stub:_swift_storeEnumTagMultiPayload
102e00eac:     	add	x8, x19, x22
102e00eb0:     	bl	0x1017e98c8    ;; CALL:fn:1017e98c8
102e00eb4:     	add	x0, x19, x22
102e00eb8:     	mov	x1, x20
102e00ebc:     	mov	w2, #0x2                ; =2
102e00ec0:     	bl	0x1035de42c    ;; CALL:stub:_swift_storeEnumTagMultiPayload
102e00ec4:     	add	x0, x19, x22
102e00ec8:     	mov	x1, x21
102e00ecc:     	mov	w2, #0x12               ; =18
102e00ed0:     	bl	0x1035de42c    ;; CALL:stub:_swift_storeEnumTagMultiPayload
102e00ed4:     	b	0x102e01224
102e00ed8:     	ldr	x9, [x25, #0x180]
102e00edc:     	mov	x8, x19
102e00ee0:     	mov	x0, x28
102e00ee4:     	mov	x1, x25
102e00ee8:     	blr	x9
102e00eec:     	ldr	x8, [x23, #0x30]
102e00ef0:     	mov	x0, x19
102e00ef4:     	mov	w1, #0x1                ; =1
102e00ef8:     	mov	x2, x27
102e00efc:     	blr	x8
102e00f00:     	cmp	w0, #0x1
102e00f04:     	b.ne	0x102e00f2c
102e00f08:     	adrp	x1, 0x10463b000
102e00f0c:     	add	x1, x1, #0xd50
102e00f10:     	adrp	x2, 0x103846000
102e00f14:     	add	x2, x2, #0xc60
102e00f18:     	mov	x0, x19
102e00f1c:     	bl	0x10000733c    ;; CALL:fn:10000733c
102e00f20:     	adrp	x27, 0x10419f000
102e00f24:     	ldr	x27, [x27, #0x738]
102e00f28:     	b	0x102e01224
102e00f2c:     	adrp	x28, 0x100c1e000
102e00f30:     	add	x28, x28, #0xf74
102e00f34:     	mov	x0, x19
102e00f38:     	ldur	x23, [x29, #-0x60]
102e00f3c:     	mov	x1, x23
102e00f40:     	mov	x2, x28
102e00f44:     	bl	0x1000082d0    ;; CALL:fn:1000082d0
102e00f48:     	adrp	x0, 0x10463c000
102e00f4c:     	add	x0, x0, #0x238
102e00f50:     	adrp	x1, 0x103843000
102e00f54:     	add	x1, x1, #0x780
102e00f58:     	bl	0x100005134    ;; CALL:fn:100005134
102e00f5c:     	ldr	x20, [x22, #0x48]
102e00f60:     	ldrb	w8, [x22, #0x50]
102e00f64:     	add	x9, x8, #0x20
102e00f68:     	bic	x19, x9, x8
102e00f6c:     	add	x1, x19, x20, lsl #1
102e00f70:     	orr	x2, x8, #0x7
102e00f74:     	bl	0x1035ddeb0    ;; CALL:stub:_swift_allocObject
102e00f78:     	stur	x0, [x29, #-0x78]
102e00f7c:     	add	x25, x0, x19
102e00f80:     	mov	x0, x23
102e00f84:     	mov	x1, x25
102e00f88:     	mov	x2, x28
102e00f8c:     	bl	0x10000828c    ;; CALL:fn:10000828c
102e00f90:     	mov	x0, #0x0                ; =0
102e00f94:     	bl	0x1017d8d0c    ;; CALL:meta:AuthFeature.AuthFeature.Action
102e00f98:     	mov	x19, x0
102e00f9c:     	mov	x0, x25
102e00fa0:     	mov	x1, x19
102e00fa4:     	mov	w2, #0x0                ; =0
102e00fa8:     	bl	0x1035de42c    ;; CALL:stub:_swift_storeEnumTagMultiPayload
102e00fac:     	mov	x0, x25
102e00fb0:     	mov	x1, x21
102e00fb4:     	mov	w2, #0x12               ; =18
102e00fb8:     	bl	0x1035de42c    ;; CALL:stub:_swift_storeEnumTagMultiPayload
102e00fbc:     	ldur	x8, [x29, #-0x58]
102e00fc0:     	ldr	x22, [x8, #0x38]
102e00fc4:     	mov	w28, #0x1               ; =1
102e00fc8:     	mov	x0, x25
102e00fcc:     	mov	w1, #0x0                ; =0
102e00fd0:     	mov	w2, #0x1                ; =1
102e00fd4:     	mov	x3, x21
102e00fd8:     	blr	x22
102e00fdc:     	ldrsw	x8, [x27, #0x14]
102e00fe0:     	ldrb	w8, [x23, x8]
102e00fe4:     	cmp	w8, #0x1
102e00fe8:     	b.ne	0x102e0101c
102e00fec:     	add	x8, x25, x20
102e00ff0:     	ldur	x0, [x29, #-0x60]
102e00ff4:     	bl	0x1017e9734    ;; CALL:fn:1017e9734
102e00ff8:     	add	x0, x25, x20
102e00ffc:     	mov	x1, x19
102e01000:     	mov	w2, #0x2                ; =2
102e01004:     	bl	0x1035de42c    ;; CALL:stub:_swift_storeEnumTagMultiPayload
102e01008:     	add	x0, x25, x20
102e0100c:     	mov	x1, x21
102e01010:     	mov	w2, #0x12               ; =18
102e01014:     	bl	0x1035de42c    ;; CALL:stub:_swift_storeEnumTagMultiPayload
102e01018:     	mov	w28, #0x0               ; =0
102e0101c:     	add	x0, x25, x20
102e01020:     	mov	x1, x28
102e01024:     	mov	w2, #0x1                ; =1
102e01028:     	mov	x3, x21
102e0102c:     	blr	x22
102e01030:     	adrp	x19, 0x10463c000
102e01034:     	add	x19, x19, #0x230
102e01038:     	adrp	x27, 0x103843000
102e0103c:     	add	x27, x27, #0x778
102e01040:     	mov	x0, x25
102e01044:     	mov	x1, x26
102e01048:     	mov	x2, x19
102e0104c:     	mov	x3, x27
102e01050:     	bl	0x100008168    ;; CALL:fn:100008168
102e01054:     	mov	x0, x26
102e01058:     	mov	x1, x24
102e0105c:     	mov	x2, x19
102e01060:     	mov	x3, x27
102e01064:     	bl	0x1000abb54    ;; CALL:fn:1000abb54
102e01068:     	ldur	x23, [x29, #-0x58]
102e0106c:     	ldr	x22, [x23, #0x30]
102e01070:     	mov	x0, x24
102e01074:     	mov	w1, #0x1                ; =1
102e01078:     	mov	x2, x21
102e0107c:     	blr	x22
102e01080:     	cmp	w0, #0x1
102e01084:     	b.ne	0x102e010ac
102e01088:     	adrp	x1, 0x10463c000
102e0108c:     	add	x1, x1, #0x230
102e01090:     	adrp	x2, 0x103843000
102e01094:     	add	x2, x2, #0x778
102e01098:     	mov	x0, x24
102e0109c:     	bl	0x10000733c    ;; CALL:fn:10000733c
102e010a0:     	adrp	x27, 0x10419f000
102e010a4:     	ldr	x27, [x27, #0x738]
102e010a8:     	b	0x102e0111c
102e010ac:     	stur	x22, [x29, #-0x80]
102e010b0:     	adrp	x2, 0x102de4000
102e010b4:     	add	x2, x2, #0xe8c
102e010b8:     	mov	x0, x24
102e010bc:     	ldur	x28, [x29, #-0x70]
102e010c0:     	mov	x1, x28
102e010c4:     	bl	0x1000082d0    ;; CALL:fn:1000082d0
102e010c8:     	adrp	x27, 0x10419f000
102e010cc:     	ldr	x27, [x27, #0x738]
102e010d0:     	mov	x0, x27
102e010d4:     	bl	0x1035de30c    ;; CALL:stub:_swift_isUniquelyReferenced_nonNull_native
102e010d8:     	tbz	w0, #0x0, 0x102e01248
102e010dc:     	ldp	x22, x8, [x27, #0x10]
102e010e0:     	add	x19, x22, #0x1
102e010e4:     	cmp	x22, x8, lsr #1
102e010e8:     	b.hs	0x102e01268
102e010ec:     	str	x19, [x27, #0x10]
102e010f0:     	ldrb	w8, [x23, #0x50]
102e010f4:     	add	x9, x8, #0x20
102e010f8:     	bic	x8, x9, x8
102e010fc:     	add	x8, x27, x8
102e01100:     	ldr	x9, [x23, #0x48]
102e01104:     	madd	x1, x9, x22, x8
102e01108:     	adrp	x2, 0x102de4000
102e0110c:     	add	x2, x2, #0xe8c
102e01110:     	mov	x0, x28
102e01114:     	bl	0x1000082d0    ;; CALL:fn:1000082d0
102e01118:     	ldur	x22, [x29, #-0x80]
102e0111c:     	adrp	x19, 0x10463c000
102e01120:     	add	x19, x19, #0x230
102e01124:     	adrp	x28, 0x103843000
102e01128:     	add	x28, x28, #0x778
102e0112c:     	add	x0, x25, x20
102e01130:     	mov	x1, x26
102e01134:     	mov	x2, x19
102e01138:     	mov	x3, x28
102e0113c:     	bl	0x100008168    ;; CALL:fn:100008168
102e01140:     	mov	x0, x26
102e01144:     	mov	x1, x24
102e01148:     	mov	x2, x19
102e0114c:     	mov	x3, x28
102e01150:     	bl	0x1000abb54    ;; CALL:fn:1000abb54
102e01154:     	mov	x0, x24
102e01158:     	mov	w1, #0x1                ; =1
102e0115c:     	mov	x2, x21
102e01160:     	blr	x22
102e01164:     	cmp	w0, #0x1
102e01168:     	b.ne	0x102e01188
102e0116c:     	adrp	x1, 0x10463c000
102e01170:     	add	x1, x1, #0x230
102e01174:     	adrp	x2, 0x103843000
102e01178:     	add	x2, x2, #0x778
102e0117c:     	mov	x0, x24
102e01180:     	bl	0x10000733c    ;; CALL:fn:10000733c
102e01184:     	b	0x102e011e8
102e01188:     	adrp	x2, 0x102de4000
102e0118c:     	add	x2, x2, #0xe8c
102e01190:     	mov	x0, x24
102e01194:     	ldur	x21, [x29, #-0x70]
102e01198:     	mov	x1, x21
102e0119c:     	bl	0x1000082d0    ;; CALL:fn:1000082d0
102e011a0:     	mov	x0, x27
102e011a4:     	bl	0x1035de30c    ;; CALL:stub:_swift_isUniquelyReferenced_nonNull_native
102e011a8:     	tbz	w0, #0x0, 0x102e01288
102e011ac:     	ldp	x20, x8, [x27, #0x10]
102e011b0:     	add	x19, x20, #0x1
102e011b4:     	cmp	x20, x8, lsr #1
102e011b8:     	b.hs	0x102e012a8
102e011bc:     	str	x19, [x27, #0x10]
102e011c0:     	ldrb	w8, [x23, #0x50]
102e011c4:     	add	x9, x8, #0x20
102e011c8:     	bic	x8, x9, x8
102e011cc:     	add	x8, x27, x8
102e011d0:     	ldr	x9, [x23, #0x48]
102e011d4:     	madd	x1, x9, x20, x8
102e011d8:     	adrp	x2, 0x102de4000
102e011dc:     	add	x2, x2, #0xe8c
102e011e0:     	mov	x0, x21
102e011e4:     	bl	0x1000082d0    ;; CALL:fn:1000082d0
102e011e8:     	adrp	x1, 0x100c1e000
102e011ec:     	add	x1, x1, #0xf74
102e011f0:     	ldur	x0, [x29, #-0x60]
102e011f4:     	bl	0x100008314    ;; CALL:fn:100008314
102e011f8:     	ldur	x19, [x29, #-0x78]
102e011fc:     	mov	x0, x19
102e01200:     	bl	0x1035de3f0    ;; CALL:stub:_swift_setDeallocating
102e01204:     	mov	x0, x25
102e01208:     	mov	w1, #0x2                ; =2
102e0120c:     	ldur	x2, [x29, #-0x68]
102e01210:     	bl	0x1035dded4    ;; CALL:stub:_swift_arrayDestroy
102e01214:     	mov	x0, x19
102e01218:     	mov	w1, #0x20               ; =32
102e0121c:     	mov	w2, #0x7                ; =7
102e01220:     	bl	0x1035ddfdc    ;; CALL:stub:_swift_deallocClassInstance
102e01224:     	mov	x0, x27
102e01228:     	sub	sp, x29, #0x50
102e0122c:     	ldp	x29, x30, [sp, #0x50]
102e01230:     	ldp	x20, x19, [sp, #0x40]
102e01234:     	ldp	x22, x21, [sp, #0x30]
102e01238:     	ldp	x24, x23, [sp, #0x20]
102e0123c:     	ldp	x26, x25, [sp, #0x10]
102e01240:     	ldp	x28, x27, [sp], #0x60
102e01244:     	ret
102e01248:     	ldr	x8, [x27, #0x10]
102e0124c:     	add	x1, x8, #0x1
102e01250:     	mov	w0, #0x0                ; =0
102e01254:     	mov	w2, #0x1                ; =1
102e01258:     	mov	x3, x27
102e0125c:     	bl	0x102db6b80    ;; CALL:fn:102db6b80
102e01260:     	mov	x27, x0
102e01264:     	b	0x102e010dc
102e01268:     	cmp	x8, #0x1
102e0126c:     	cset	w0, hi
102e01270:     	mov	x1, x19
102e01274:     	mov	w2, #0x1                ; =1
102e01278:     	mov	x3, x27
102e0127c:     	bl	0x102db6b80    ;; CALL:fn:102db6b80
102e01280:     	mov	x27, x0
102e01284:     	b	0x102e010ec
102e01288:     	ldr	x8, [x27, #0x10]
102e0128c:     	add	x1, x8, #0x1
102e01290:     	mov	w0, #0x0                ; =0
102e01294:     	mov	w2, #0x1                ; =1
102e01298:     	mov	x3, x27
102e0129c:     	bl	0x102db6b80    ;; CALL:fn:102db6b80
102e012a0:     	mov	x27, x0
102e012a4:     	b	0x102e011ac
102e012a8:     	cmp	x8, #0x1
102e012ac:     	cset	w0, hi
102e012b0:     	mov	x1, x19
102e012b4:     	mov	w2, #0x1                ; =1
102e012b8:     	mov	x3, x27
102e012bc:     	bl	0x102db6b80    ;; CALL:fn:102db6b80
102e012c0:     	mov	x27, x0
102e012c4:     	b	0x102e011bc
