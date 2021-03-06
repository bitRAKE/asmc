; _FINITE.ASM--
;
; Copyright (c) The Asmc Contributors. All rights reserved.
; Consult your license regarding permissions and restrictions.
;
include float.inc

.code

_finite proc __cdecl d:REAL8

    mov edx,dword ptr d[4]
    shr edx,32 - D_EXPBITS - 1
    and edx,D_EXPMASK
    xor eax,eax
    .if edx != D_EXPMASK
	inc eax
    .endif
    ret

_finite endp

    end
