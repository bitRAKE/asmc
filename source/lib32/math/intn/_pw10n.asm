; _pw10n() - returns the base to the power of 10
;
include intn.inc
include malloc.inc

.code

_pw10n proc uses esi edi ebx base:ptr, exponent:sdword, n:dword

local h, e

    mov eax,n
    shl eax,2
    mov e,alloca(eax)
    mov ecx,n
    mov edi,eax
    xor eax,eax
    rep stosd
    mov eax,e
    mov dword ptr [eax],10

    mov ebx,n
    shr ebx,1
    mov esi,base
    lea edi,[esi+ebx*4] ; high product
    .if !ebx
        lea edi,h
        mov ebx,1
    .endif

    .while exponent > 0

        _mulnd(esi, e, edi, ebx)
        dec exponent
    .endw
    mov eax,esi
    ret

_pw10n endp

    end
