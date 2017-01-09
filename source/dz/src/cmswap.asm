; CMSWAP.ASM--
; Copyright (C) 2016 Doszip Developers -- see LICENSE.TXT

include doszip.inc
include string.inc

	.code

cmswap	PROC USES esi edi
	.if panel_stateab()
		mov	esi,config.c_apath.ws_flag
		mov	edi,config.c_bpath.ws_flag
		mov	eax,panela
		call	panel_hide
		mov	eax,panelb
		call	panel_hide
		memxchg(addr config.c_fcb_indexa, addr config.c_fcb_indexb, 8)
		memxchg(addr spanela.pn_fcb_index, addr spanelb.pn_fcb_index, 8)
		memxchg(addr config.c_apath, addr config.c_bpath, SIZE S_WSUB)
		xor	esi,_W_PANELID
		xor	edi,_W_PANELID
		mov	config.c_apath.ws_flag,edi
		mov	config.c_bpath.ws_flag,esi
		xor	config.c_cflag,_C_PANELID
		mov	eax,panela
		call	panel_show
		mov	eax,panelb
		call	panel_show
		mov	eax,1
	.endif
	ret
cmswap	ENDP

	END
