==== function 0x100b2ae8c (size 0x2c)
100b2ae8c:     	adrp	x3, 0x104653000
100b2ae90:     	add	x3, x3, #0xfb
100b2ae94:     	mov	x1, #0x5241             ; =21057
100b2ae98:     	movk	x1, #0x5f43, lsl #16
100b2ae9c:     	movk	x1, #0x4146, lsl #32
100b2aea0:     	movk	x1, #0x454b, lsl #48
100b2aea4:     	mov	x2, #0x415f             ; =16735
100b2aea8:     	movk	x2, #0x5455, lsl #16
100b2aeac:     	movk	x2, #0x48, lsl #32
100b2aeb0:     	movk	x2, #0xed00, lsl #48    ;; STR:ARC_FAKE_AUTH
100b2aeb4:     	b	0x100b2aeb8    ;; TAIL:fn:100b2aeb8
