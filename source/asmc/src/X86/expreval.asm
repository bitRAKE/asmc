
;; expression evaluator.

include stddef.inc

include asmc.inc
include crtl.inc
include parser.inc
include reswords.inc
include expreval.inc
include segment.inc
include proc.inc
include assume.inc
include tokenize.inc
include types.inc
include label.inc
include atofloat.inc
include quadmath.inc

externdef StackAdj:uint_t

CALLBACKC(lpfnasmerr, :int_t, :vararg)
CALLBACKC(unaryop_t, :int_t, :expr_t, :expr_t, :asym_t, :string_t)

    .data

thissym     asym_t 0
nullstruct  asym_t 0
nullmbr     asym_t 0
fnasmerr    lpfnasmerr 0


LS_SHORT equ 0xFF01
LS_FAR16 equ 0xFF05
LS_FAR32 equ 0xFF06

    .code

    option procalign:4
    option proc:private

noasmerr proc msg:int_t, args:vararg

    mov eax,ERROR
    ret

noasmerr endp

    assume ecx:expr_t

init_expr proc fastcall opnd:expr_t

    xor eax,eax
    mov [ecx].value,        eax
    mov [ecx].hvalue,       eax
    mov [ecx+8],            eax ; .hlvalue
    mov [ecx+12],           eax
    mov [ecx].quoted_string,eax
    mov [ecx].base_reg,     eax
    mov [ecx].idx_reg,      eax
    mov [ecx].label_tok,    eax
    mov [ecx].override,     eax
    mov [ecx].inst,         EMPTY
    mov [ecx].kind,         EXPR_EMPTY
    mov [ecx].mem_type,     MT_EMPTY
    mov [ecx].scale,        al
    mov [ecx].Ofssize,      USE_EMPTY
    mov [ecx].flags,        al
    mov [ecx].sym,          eax
    mov [ecx].mbr,          eax
    mov [ecx].type,         eax
    ret

init_expr endp

TokenAssign proc fastcall uses esi edi ecx opnd1:expr_t, opnd2:expr_t

    ;; note that offsetof() is used. This means, don't change position
    ;; of field <type> in expr!
    mov esi,edx
    mov edi,ecx
    mov ecx,offsetof( expr, type )
    rep movsb
    ret

TokenAssign endp

    assume ecx:tok_t

get_precedence proc fastcall item:tok_t

    mov al,[ecx].token
    .switch al
    .case T_UNARY_OPERATOR
    .case T_BINARY_OPERATOR
        .return [ecx].precedence
    .case T_OP_BRACKET
    .case T_OP_SQ_BRACKET
        mov eax,1
        .if ModuleInfo.m510
            mov eax,9
        .endif
        .return
    .case T_DOT
        .return 2
    .case T_COLON
        .return 3
    .case '*'
    .case '/'
        .return 8
    .case '+'
    .case '-'
        mov eax,7
        .if [ecx].specval
            mov eax,9
        .endif
        .return
    .endsw
    fnasmerr( 2008, [ecx].string_ptr )
    mov eax,ERROR
    ret

get_precedence endp

GetTypeSize proc fastcall mem_type:byte, ofssize:int_t

    .if cl == MT_ZWORD
        .return 64
    .endif
    .if !( cl & MT_SPECIAL )
        and ecx,MT_SIZE_MASK
        inc ecx
        .return ecx
    .endif
    .if edx == USE_EMPTY
        movzx edx,ModuleInfo.Ofssize
    .endif
    .if cl == MT_NEAR
        mov eax,2
        mov ecx,edx
        shl eax,cl
        or  eax,0xFF00
    .elseif cl == MT_FAR
        mov eax,LS_FAR16
        .if dl != USE16
            mov eax,2
            mov ecx,edx
            shl eax,cl
            add eax,2
            or  eax,0xFF00
        .endif
    .else
        xor eax,eax
    .endif
    ret

GetTypeSize endp

    assume ecx:dsym_t

GetRecordMask proc fastcall uses esi edi ebx rec:dsym_t

    xor eax,eax
    xor edx,edx
    mov ebx,[ecx].structinfo
    mov ebx,[ebx].struct_info.head

    .for ( : ebx : ebx = [ebx].sfield.next )

        mov ecx,[ebx].sfield.sym._offset
        mov edi,[ebx].sfield.sym.total_size
        add edi,ecx

        .for ( : ecx < edi : ecx++ )

            mov esi,1
            .if ecx < 32
                shl esi,cl
                or  eax,esi
            .else
                sub ecx,32
                shl esi,cl
                or  edx,esi
                add ecx,32
            .endif
        .endf
    .endf
    ret

GetRecordMask endp

    assume ebx:tok_t
    assume edi:expr_t
    assume ecx:nothing

get_operand proc uses esi edi ebx opnd:expr_t, idx:ptr int_t, tokenarray:tok_t, flags:byte

    local tmp:string_t
    local sym:asym_t
    local i:int_t
    local j:int_t
    local labelbuff[16]:char_t

    mov edx,idx
    mov eax,[edx]
    mov i,eax

    mov edi,opnd
    mov ebx,tokenarray
    shl eax,4
    add ebx,eax

    mov al,[ebx].token

    .switch al
    .case '&' ; v2.30.24 -- mov mem,&mem
        .if ( Options.strict_masm_compat == FALSE && i > 2 && \
              [ebx-16].token == T_COMMA && [ebx-32].token != T_REG )
            inc i
            inc dword ptr [edx]
            add ebx,16
            mov al,[ebx].token
            .gotosw
        .endif
        .return fnasmerr( 2008, [ebx].tokpos )
    .case T_NUM
        mov [edi].kind,EXPR_CONST
        _atoow( edi, [ebx].string_ptr, [ebx].numbase, [ebx].itemlen )
        .endc
    .case T_STRING
        .if ( [ebx].string_delim != '"' && [ebx].string_delim != "'" )
            .endc .if ( [edi].flags & E_IS_OPEATTR )

            mov ecx,[ebx].string_ptr
            mov al,[ecx]
            .if ( [ebx].string_delim == 0 && ( al == '"' || al == "'" ) )
                fnasmerr( 2046 )
            .elseif [ebx].string_delim == '{'
                or  [ebx].hll_flags,T_EVEX_OPT
                mov [edi].kind,EXPR_EMPTY
                .endc
            .else
                fnasmerr( 2167, [ebx].tokpos )
            .endif
            .return ERROR
        .endif
        mov [edi].kind,EXPR_CONST
        mov [edi].quoted_string,ebx
        mov edx,[ebx].string_ptr
        inc edx
        mov ecx,[ebx].stringlen
        .if ecx > 16
            mov ecx,16
        .endif
        .for : ecx: ecx--
            mov al,[edx]
            inc edx
            mov [edi].chararray[ecx-1],al
        .endf
        .endc
    .case T_REG
        mov [edi].kind,EXPR_REG
        mov [edi].base_reg,ebx
        imul eax,[ebx].tokval,special_item
        movzx eax,SpecialTable[eax].cpu
        mov ecx,ModuleInfo.curr_cpu
        mov edx,ecx
        and ecx,P_EXT_MASK
        and edx,P_CPU_MASK
        mov esi,eax
        and esi,P_CPU_MASK

        .if ( ( eax & P_EXT_MASK ) && !( eax & ecx ) || edx < esi )

            .if flags & EXPF_IN_SQBR
                mov [edi].kind,EXPR_ERROR
                fnasmerr(2085)
            .else
                .return fnasmerr(2085)
            .endif
        .endif

        .if ( ( i > 0 && [ebx-16].tokval == T_TYPEOF ) || \
              ( i > 1 && [ebx-16].token == T_OP_BRACKET && [ebx-32].tokval == T_TYPEOF ) )

             ; v2.24 [reg + type reg] | [reg + type(reg)]

        .elseif flags & EXPF_IN_SQBR

            imul eax,[ebx].tokval,special_item
            .if ( SpecialTable[eax].sflags & SFR_IREG )
                or [edi].flags,E_INDIRECT or E_ASSUMECHECK
            .elseif ( SpecialTable[eax].value & OP_SR )
                .if( [ebx+16].token != T_COLON || \
                   ( ModuleInfo.strict_masm_compat && [ebx+32].token == T_REG ) )
                    .return fnasmerr(2032)
                .endif
            .else
                .if ( [edi].flags & E_IS_OPEATTR )
                    mov [edi].kind,EXPR_ERROR
                .else
                    .return fnasmerr(2031)
                .endif
            .endif
        .endif
        .endc
    .case T_ID
        mov esi,[ebx].string_ptr
        .if ( [edi].flags & E_IS_DOT )
            xor eax,eax
            mov [edi].value,eax
            .if [edi].type
                SearchNameInStruct( [edi].type, esi, edi, 0 )
            .endif
            .if eax == NULL
                .if SymFind(esi)
                    .if [eax].asym.state == SYM_TYPE
                        mov ecx,[edi].type
                        .if !( eax == ecx || ( ecx && !( [ecx].asym.flag & S_ISDEFINED ) ) || ModuleInfo.oldstructs )
                            xor eax,eax
                        .endif
                    .elseif !( ModuleInfo.oldstructs && ( [eax].asym.state == SYM_STRUCT_FIELD || \
                              [eax].asym.state == SYM_EXTERNAL || [eax].asym.state == SYM_INTERNAL ) )
                        xor eax,eax
                    .endif
                .endif
            .endif
        .else
            mov edx,[esi]
            or  dh,0x20
            .if ( dl == '@' && !( edx & 0x00FF0000 ) )
                .if dh == 'b'
                    mov esi,GetAnonymousLabel( &labelbuff, 0 )
                .elseif dh == 'f'
                    mov esi,GetAnonymousLabel( &labelbuff, 1 )
                .endif
            .endif
            SymFind(esi)
        .endif
        .if ( eax == NULL || [eax].asym.state == SYM_UNDEFINED || \
            ( [eax].asym.state == SYM_TYPE && [eax].asym.typekind == TYPE_NONE ) || \
              [eax].asym.state == SYM_MACRO || [eax].asym.state == SYM_TMACRO )

            .if ( [edi].flags & E_IS_OPEATTR )
                mov [edi].kind,EXPR_ERROR
                .endc
            .endif
            .if ( eax && ( [eax].asym.state == SYM_MACRO || [eax].asym.state == SYM_TMACRO ) )
                .return fnasmerr( 2148, [eax].asym.name )
            .endif
            .if ( Parse_Pass == PASS_1 && !( flags & EXPF_NOUNDEF ) )
                .if eax == NULL
                    mov ecx,[edi].type
                    .if ecx == NULL
                        SymLookup(esi)
                        push eax
                        mov [eax].asym.state,SYM_UNDEFINED
                        sym_add_table( &SymTables[TAB_UNDEF*symbol_queue], eax )
                        pop eax
                    .elseif [ecx].asym.typekind != TYPE_NONE
                        .return fnasmerr(2006, esi)
                    .else
                        mov eax,nullmbr
                        .if !eax
                            SymAlloc("")
                        .endif
                        mov [edi].mbr,eax
                        mov [edi].kind,EXPR_CONST
                        .endc
                    .endif
                .endif
            .else

                .if ( Options.strict_masm_compat == FALSE && eax == NULL )

                    .if !_stricmp(esi, "defined")

                        .if ( i && [ebx+16].token == T_OP_BRACKET )

                            add i,2
                            add ebx,32
                            mov [edi].kind,EXPR_CONST
                            mov dword ptr [edi].llvalue,0
                            mov dword ptr [edi].llvalue[4],0

                            ;; added v2.28.17: defined(...) returns -1

                            mov ecx,idx
                            mov eax,i
                            .if [ebx].token == T_CL_BRACKET
                                mov [ecx],eax
                                dec [edi].value ; <> -- defined()
                                dec [edi].hvalue
                                .endc
                            .endif
                            .if [ebx].token == T_NUM && [ebx+16].token == T_CL_BRACKET
                                dec [edi].value ; <> -- defined()
                                dec [edi].hvalue
                                inc eax
                                mov [ecx],eax
                                .endc
                            .endif

                            .if [ebx].token == T_ID && [ebx+16].token == T_CL_BRACKET

                                inc eax
                                mov [ecx],eax
                                .if SymFind([ebx].string_ptr)
                                    .if [eax].asym.state != SYM_UNDEFINED
                                        dec [edi].value ; symbol defined
                                        dec [edi].hvalue
                                        .endc
                                    .endif
                                .endif

                                ;; -- symbol not defined --

                                .endc .if ( [ebx+32].token == T_FINAL || \
                                            [ebx+32].tokval != T_AND  || \
                                            [ebx-48].tokval == T_NOT )

                                    ;; [not defined(symbol)] - return 0


                                ;; [defined(symbol) and] - return 0 and skip rest of line... */
                                add ebx,48
                                mov edx,i
                                add edx,3
                                .for ( ecx = 0: edx < Token_Count: edx++, ebx += 16 )
                                    .if ( [ebx].token == T_CL_BRACKET )
                                        .break .if ( ecx == 0 )
                                        dec ecx
                                    .elseif ( [ebx].token == T_OP_BRACKET )
                                        inc ecx
                                    .endif
                                .endf
                                dec edx
                                mov ecx,idx
                                mov [ecx],edx
                                .endc
                            .endif
                        .endif
                    .endif
                .endif
                .if byte ptr [esi+1] == '&'
                    lea esi,@CStr("@@")
                .endif
                .return fnasmerr( 2006, esi )
            .endif
        .elseif ( [eax].asym.state == SYM_ALIAS )
            mov eax,[eax].asym.substitute
        .endif
        or [eax].asym.flag,S_USED

        .switch [eax].asym.state
        .case SYM_TYPE
            mov ecx,[eax].esym.structinfo
            .if ( [eax].asym.typekind != TYPE_TYPEDEF && [ecx].struct_info.flags & STINF_ISOPEN )
                mov [edi].kind,EXPR_ERROR
                .endc
            .endif
            .for ( : [eax].asym.type: eax = [eax].asym.type )
            .endf
            mov cl,[eax].asym.mem_type
            mov [edi].kind,EXPR_CONST
            mov [edi].mem_type,cl
            or  [edi].flags,E_IS_TYPE
            mov [edi].type,eax
            and ecx,MT_SPECIAL_MASK
            .if [eax].asym.typekind == TYPE_RECORD
                GetRecordMask(eax)
                mov [edi].value,eax
                mov [edi].hvalue,edx
            .elseif ( ecx == MT_ADDRESS )
                .if [eax].asym.mem_type == MT_PROC
                    mov ecx,[eax].asym.total_size
                    mov [edi].value,ecx
                    mov cl,[eax].asym.Ofssize
                    mov [edi].Ofssize,cl
                .else
                    movzx edx,[eax].asym.Ofssize
                    mov [edi].value,GetTypeSize([eax].asym.mem_type, edx)
                .endif
            .else
                mov [edi].value,[eax].asym.total_size
            .endif
            .endc
        .case SYM_STRUCT_FIELD
            mov [edi].mbr,eax
            mov [edi].kind,EXPR_CONST
            mov ecx,[eax].asym._offset
            add [edi].value,ecx
            .for : [eax].asym.type: eax = [eax].asym.type
            .endf
            mov cl,[eax].asym.mem_type
            mov [edi].mem_type,cl
            .if [eax].asym.state == SYM_TYPE && [eax].asym.typekind != TYPE_TYPEDEF
                mov [edi].type,eax
            .else
                mov [edi].type,NULL
            .endif
            .endc
        .default

            mov esi,eax
            assume esi:asym_t

            mov [edi].kind,EXPR_ADDR
            .if ( [esi].flag & S_PREDEFINED && [esi].sfunc_ptr )
                [esi].sfunc_ptr(esi, NULL)
            .endif
            .if ( [esi].state == SYM_INTERNAL && [esi]._segment == NULL )
                mov [edi].kind,EXPR_CONST
                mov [edi].uvalue,[esi].uvalue
                mov [edi].hvalue,[esi].value3264
                mov [edi].mem_type,[esi].mem_type
                .if al == MT_REAL16 && !ModuleInfo.strict_masm_compat
                    mov [edi].kind,EXPR_FLOAT
                    mov [edi].float_tok,NULL
                    mov dword ptr [edi].hlvalue,[esi].total_length
                    mov dword ptr [edi].hlvalue[4],[esi].ext_idx
                .endif
            .elseif [esi].state == SYM_EXTERNAL && [esi].mem_type == MT_EMPTY && \
                 !( [esi].sint_flag & SINT_ISCOM )
                or  [edi].flags,E_IS_ABS
                mov [edi].sym,esi
            .else
                mov [edi].label_tok,ebx
                mov ecx,[esi].type
                .if ecx && [ecx].asym.mem_type != MT_EMPTY
                    mov [edi].mem_type,[ecx].asym.mem_type
                .else
                    mov [edi].mem_type,[esi].mem_type
                .endif
                .if [esi].state == SYM_STACK
                    mov eax,[esi]._offset
                    add eax,StackAdj
                    cdq
                    mov [edi].value,eax
                    mov [edi].hvalue,edx
                    or  [edi].flags,E_INDIRECT
                    mov [edi].base_reg,ebx
                    mov ecx,CurrProc
                    mov ecx,[ecx].esym.procinfo
                    movzx eax,[ecx].proc_info.basereg
                    mov [ebx].tokval,eax
                    imul eax,eax,special_item
                    mov al,SpecialTable[eax].bytval
                    mov [ebx].bytval,al
                .endif
                mov [edi].sym,esi
                .for : [esi].type : esi = [esi].type
                .endf
                .if [esi].state == SYM_TYPE && [esi].typekind != TYPE_TYPEDEF
                    mov [edi].type,esi
                .else
                    mov [edi].type,NULL
                .endif
            .endif
            .endc
        .endsw
        .endc
    .case T_STYPE
        mov [edi].kind,EXPR_CONST
        imul ecx,[ebx].tokval,special_item
        mov [edi].mem_type,SpecialTable[ecx].bytval
        mov eax,SpecialTable[ecx].sflags
        mov [edi].Ofssize,al
        mov [edi].value,GetTypeSize([edi].mem_type, eax)
        or  [edi].flags,E_IS_TYPE
        mov [edi].type,NULL
        .endc
    .case T_RES_ID
        .if ( [ebx].tokval == T_FLAT )
            .if !( flags & EXPF_NOUNDEF )
                mov eax,ModuleInfo.curr_cpu
                and eax,P_CPU_MASK
                .return fnasmerr(2085) .if eax < P_386
                DefineFlatGroup()
            .endif
            mov [edi].sym,ModuleInfo.flat_grp
            .return(ERROR) .if !eax
            mov [edi].label_tok,ebx
            mov [edi].kind,EXPR_ADDR
        .else
            .return fnasmerr( 2008, [ebx].string_ptr )
        .endif
        .endc
    .case T_FLOAT
        mov [edi].kind,EXPR_FLOAT
        mov [edi].float_tok,ebx
        .endc
    .default
        .if ( [edi].flags & E_IS_OPEATTR )
            .if ( [ebx].token == T_FINAL || [ebx].token == T_CL_BRACKET || \
                  [ebx].token == T_CL_SQ_BRACKET )
                .return( NOT_ERROR )
            .endif
            .endc
        .endif
        mov ecx,[ebx].string_ptr
        movzx eax,byte ptr [ecx]
        mov al,_ltype[eax+1]
        and eax,_UPPER or _LOWER
        .if [ebx].token == T_BAD_NUM
            fnasmerr( 2048, ecx )
        .elseif [ebx].token == T_COLON
            fnasmerr( 2009 )
        .elseif eax
            fnasmerr( 2016, [ebx].tokpos )
        .else
            fnasmerr( 2008, [ebx].tokpos )
        .endif
        .return
    .endsw
    mov ecx,idx
    inc dword ptr [ecx]
    mov eax,NOT_ERROR
    ret

get_operand endp

    assume ecx:expr_t
    assume edx:expr_t

check_both proc opnd1:expr_t, opnd2:expr_t,  type1:int_t, type2:int_t

    mov ecx,opnd1
    mov edx,opnd2
    .return(1) .if [ecx].kind == type1 && [edx].kind == type2
    .return(1) .if [ecx].kind == type2 && [edx].kind == type1
    xor eax,eax
    ret

check_both endp

index_connect proc fastcall opnd1:expr_t, opnd2:expr_t

    mov eax,[edx].base_reg
    .if eax != NULL
        .if [ecx].base_reg == NULL
            mov [ecx].base_reg,eax
        .elseif [ecx].idx_reg == NULL
            .if [eax].asm_tok.bytval == 4
                mov [ecx].idx_reg,[ecx].base_reg
                mov [ecx].base_reg,[edx].base_reg
            .else
                mov [ecx].idx_reg,eax
            .endif
        .else
            .return fnasmerr(2030)
        .endif
        or [ecx].flags,E_INDIRECT
    .endif
    .if [edx].idx_reg != NULL
        .if [ecx].idx_reg == NULL
            mov [ecx].idx_reg,[edx].idx_reg
            mov [ecx].scale,[edx].scale
        .else
            .return fnasmerr(2030)
        .endif
        or [ecx].flags,E_INDIRECT
    .endif
    mov eax,NOT_ERROR
    ret

index_connect endp

MakeConst proc fastcall opnd:expr_t

    .return .if ( ( [ecx].kind != EXPR_ADDR ) || [ecx].flags & E_INDIRECT )
    .if [ecx].sym
        .return .if Parse_Pass > PASS_1
        mov eax,[ecx].sym
        .return .if !( ( [eax].asym.state == SYM_UNDEFINED && [ecx].inst == EMPTY ) || \
            ( [eax].asym.state == SYM_EXTERNAL && [eax].asym.sint_flag & SINT_WEAK && \
              [ecx].flags & E_IS_ABS ) )
        mov [ecx].value,1
    .endif
    mov [ecx].label_tok,NULL
    mov eax,[ecx].mbr
    .if eax
        .return .if [eax].asym.state != SYM_STRUCT_FIELD
    .endif
    .return .if [ecx].override != NULL
    mov [ecx].inst,EMPTY
    mov [ecx].kind,EXPR_CONST
    and [ecx].flags,not E_EXPLICIT
    mov [ecx].mem_type,MT_EMPTY
    ret

MakeConst endp

    assume ebx:asym_t
    assume eax:asym_t

MakeConst2 proc fastcall uses ebx opnd1:expr_t, opnd2:expr_t

    mov eax,[ecx].sym
    .if [eax].state == SYM_EXTERNAL
        .return fnasmerr(2018, [eax].name)
    .endif
    mov ebx,[edx].sym
    .if ( ( [eax].state != SYM_UNDEFINED && [ebx]._segment != [eax]._segment && \
            [ebx].state != SYM_UNDEFINED ) || [ebx].state == SYM_EXTERNAL )
        .return fnasmerr(2025)
    .endif
    mov eax,[ecx].sym
    mov [ecx].kind,EXPR_CONST
    mov [edx].kind,EXPR_CONST
    add [ecx].value,[eax]._offset
    add [edx].value,[ebx]._offset
    mov eax,NOT_ERROR
    ret

MakeConst2 endp

ConstError proc fastcall opnd1:expr_t, opnd2:expr_t
    .return(NOT_ERROR) .if ( [ecx].flags & E_IS_OPEATTR )
    .if [ecx].kind == EXPR_FLOAT || [edx].kind == EXPR_FLOAT
        fnasmerr(2050)
    .else
        fnasmerr(2026)
    .endif
    ret
ConstError endp

fix_struct_value proc fastcall opnd:expr_t
    mov eax,[ecx].mbr
    .if eax && [eax].state == SYM_TYPE
        add [ecx].value,[eax].total_size
        mov [ecx].mbr,NULL
    .endif
    ret
fix_struct_value endp

check_direct_reg proc fastcall opnd1:expr_t, opnd2:expr_t
    .if [ecx].kind == EXPR_REG && !( [ecx].flags & E_INDIRECT ) || \
        [edx].kind == EXPR_REG && !( [edx].flags & E_INDIRECT )
        .return ERROR
    .endif
    mov eax,NOT_ERROR
    ret
check_direct_reg endp

    assume ecx:asym_t

GetSizeValue proc fastcall sym:asym_t
    movzx edx,[ecx].mem_type
    .if edx == MT_PTR
        mov edx,MT_NEAR
        .if [ecx].sint_flag & SINT_ISFAR
            mov edx,MT_FAR
        .endif
    .endif
    SizeFromMemtype(dl, [ecx].Ofssize, [ecx].type)
    ret
GetSizeValue endp

    assume ecx:expr_t

IsOffset proc fastcall opnd:expr_t
    xor eax,eax
    .if [ecx].mem_type == MT_EMPTY
        .if [ecx].inst == T_OFFSET || [ecx].inst == T_IMAGEREL || \
            [ecx].inst == T_SECTIONREL || [ecx].inst == T_LROFFSET
            inc eax
        .endif
    .endif
    ret
IsOffset endp

invalid_operand proc opnd:expr_t, oprtr:string_t, operand:string_t
    mov ecx,opnd
    .if !( [ecx].flags & E_IS_OPEATTR )
        fnasmerr(3018, _strupr(oprtr), operand)
    .endif
    mov eax,ERROR
    ret
invalid_operand endp

sizlen_op proc oper:int_t, opnd1:expr_t, opnd2:expr_t, sym:asym_t, name:string_t

    mov ecx,opnd1
    mov edx,opnd2
    mov eax,sym
    mov [ecx].kind,EXPR_CONST

    .if eax
        .if [eax].state == SYM_STRUCT_FIELD || [eax].state == SYM_STACK
        .elseif [eax].state == SYM_UNDEFINED
            mov [ecx].kind,EXPR_ADDR
            mov [ecx].sym,eax
        .elseif ( ( [eax].state == SYM_EXTERNAL || [eax].state == SYM_INTERNAL) && \
                    [eax].mem_type != MT_EMPTY && [eax].mem_type != MT_FAR && \
                    [eax].mem_type != MT_NEAR )
        .elseif [eax].state == SYM_GRP || [eax].state == SYM_SEG
            .return fnasmerr(2143)
        .elseif oper == T_DOT_SIZE || oper == T_DOT_LENGTH
        .else
            .return fnasmerr(2143)
        .endif
    .endif
    .switch oper
    .case T_DOT_LENGTH
        .if [eax].flag & S_ISDATA
            mov [ecx].value,[eax].first_length
        .else
            mov [ecx].value,1
        .endif
        .endc
    .case T_LENGTHOF
        .if [edx].kind == EXPR_CONST
            mov eax,[edx].mbr
            mov [ecx].value,[eax].total_length
        .elseif [eax].state == SYM_EXTERNAL && !( [eax].sint_flag & SINT_ISCOM )
            mov [ecx].value,1
        .else
            mov [ecx].value,[eax].total_length
        .endif
        .endc
    .case T_DOT_SIZE
        .if eax == NULL
            mov al,[edx].mem_type
            and eax,MT_SPECIAL_MASK
            .if eax == MT_ADDRESS
                mov eax,[edx].value
                or  eax,0xFF00
                mov [ecx].value,eax
            .else
                mov [ecx].value,[edx].value
            .endif
        .elseif [eax].flag & S_ISDATA
            mov [ecx].value,[eax].first_size
        .elseif [eax].state == SYM_STACK
            GetSizeValue(eax)
            mov ecx,opnd1
            mov [ecx].value,eax
        .elseif [eax].mem_type == MT_NEAR
            mov ecx,GetSymOfssize(eax)
            mov eax,2
            shl eax,cl
            or  eax,0xFF00
            mov ecx,opnd1
            mov [ecx].value,eax
        .elseif [eax].mem_type == MT_FAR
            .if GetSymOfssize(eax)
                mov eax,LS_FAR32
            .else
                mov eax,LS_FAR16
            .endif
            mov ecx,opnd1
            mov [ecx].value,eax
        .else
            GetSizeValue(eax)
            mov ecx,opnd1
            mov [ecx].value,eax
        .endif
        .endc
    .case T_SIZEOF
        .if eax == NULL
            mov eax,[edx].type
            .if [edx].flags & E_IS_TYPE && eax && [eax].typekind == TYPE_RECORD
                mov [ecx].value,[eax].total_size
            .else
                mov [ecx].value,[edx].value
            .endif
        .elseif [eax].state == SYM_EXTERNAL && !( [eax].sint_flag & SINT_ISCOM )
            GetSizeValue(eax)
            mov ecx,opnd1
            mov [ecx].value,eax
        .else
            mov [ecx].value,[eax].total_size
        .endif
        .endc
    .endsw
    mov eax,NOT_ERROR
    ret

sizlen_op endp

type_op proc oper:int_t, opnd1:expr_t, opnd2:expr_t, sym:asym_t, name:string_t

    mov ecx,opnd1
    mov edx,opnd2
    mov eax,sym
    mov [ecx].kind,EXPR_CONST

    .if [edx].inst != EMPTY && [edx].mem_type != MT_EMPTY
        mov [edx].inst,EMPTY
        xor eax,eax
    .endif
    .if [edx].inst != EMPTY
        .if [edx].sym
            .switch [edx].inst
            .case T_DOT_LOW
            .case T_DOT_HIGH
                mov [ecx].value,1
                .endc
            .case T_LOWWORD
            .case T_HIGHWORD
                mov [ecx].value,2
                .endc
            .case T_LOW32
            .case T_HIGH32
                mov [ecx].value,4
                .endc
            .case T_LOW64
            .case T_HIGH64
                mov [ecx].value,8
                .endc
            .case T_OFFSET
            .case T_LROFFSET
            .case T_SECTIONREL
            .case T_IMAGEREL
                mov ecx,GetSymOfssize([edx].sym)
                mov eax,2
                shl eax,cl
                mov ecx,opnd1
                mov [ecx].value,eax
                or  [ecx].flags,E_IS_TYPE
                .endc
            .endsw
        .endif
    .elseif eax == NULL
        mov eax,[edx].type
        .if ( [edx].flags & E_IS_TYPE )
            .if eax && [eax].typekind == TYPE_RECORD
                mov [edx].value,[eax].total_size
            .endif
            TokenAssign(ecx, edx)
            mov [ecx].type,[edx].type
        .elseif ( [edx].kind == EXPR_REG && !( [edx].flags & E_INDIRECT ) )

            mov eax,[edx].base_reg
            assume eax:nothing
            SizeFromRegister([eax].asm_tok.tokval)
            mov [ecx].value,eax
            or  [ecx].flags,E_IS_TYPE
            mov eax,[edx].base_reg
            imul eax,[eax].asm_tok.tokval,special_item
            .if ( ( SpecialTable[eax].value & OP_RGT8 ) && [ecx].mem_type == MT_EMPTY && \
                  byte ptr [ecx].value == ModuleInfo.wordsize )
                mov eax,[edx].base_reg
                GetStdAssumeEx([eax].asm_tok.bytval)
            .else
                xor eax,eax
            .endif
            assume eax:asym_t
            .if eax
                mov [ecx].type,eax
                mov dl,[eax].mem_type
                mov [ecx].mem_type,dl
                mov [ecx].value,[eax].total_size
            .else
                mov [ecx].mem_type,[edx].mem_type
                mov [ecx].type,[edx].type
                .if [ecx].mem_type == MT_EMPTY
                    MemtypeFromSize([ecx].value, &[ecx].mem_type)
                .endif
            .endif
        .elseif [edx].mem_type != MT_EMPTY || [edx].flags & E_EXPLICIT
            .if [edx].mem_type != MT_EMPTY
                SizeFromMemtype([edx].mem_type, [edx].Ofssize, [edx].type)
                mov ecx,opnd1
                mov edx,opnd2
                mov [ecx].value,eax
                mov [ecx].mem_type,[edx].mem_type
            .else
                mov eax,[edx].type
                .if eax
                    push [eax].total_size
                    pop [ecx].value
                    mov [ecx].mem_type,[eax].mem_type
                .endif
            .endif
            or  [ecx].flags,E_IS_TYPE
            mov [ecx].type,[edx].type
        .else
            mov [ecx].value,0
        .endif
    .elseif [eax].state == SYM_UNDEFINED
        mov [ecx].kind,EXPR_ADDR
        mov [ecx].sym,eax
        or  [ecx].flags,E_IS_TYPE
    .elseif [eax].mem_type == MT_TYPE && !( [edx].flags & E_EXPLICIT )
        or  [ecx].flags,E_IS_TYPE
        mov eax,[eax].type
        mov [ecx].type,eax
        mov edx,[eax].total_size
        mov [ecx].value,edx
        mov [ecx].mem_type,[eax].mem_type
    .else
        or  [ecx].flags,E_IS_TYPE
        .if [ecx].mem_type == MT_EMPTY
            mov [ecx].mem_type,[edx].mem_type
        .endif
        mov eax,sym
        .if [edx].type && [edx].mbr == NULL
            mov [ecx].type_tok,[edx].type_tok
            mov [ecx].type,[edx].type
            mov [ecx].value,[eax].total_size
        .elseif [eax].mem_type == MT_PTR
            mov [ecx].type_tok,[edx].type_tok
            mov eax,sym
            mov ecx,MT_NEAR
            .if [eax].sint_flag & SINT_ISFAR
                mov ecx,MT_FAR
            .endif
            SizeFromMemtype(cl, [eax].Ofssize, NULL)
            mov ecx,opnd1
            mov [ecx].value,eax
        .elseif [eax].mem_type == MT_NEAR
            mov ecx,GetSymOfssize(eax)
            mov eax,2
            shl eax,cl
            or  eax,0xFF00
            mov ecx,opnd1
            mov [ecx].value,eax
        .elseif [eax].mem_type == MT_FAR
            .if GetSymOfssize(eax)
                mov eax,LS_FAR32
            .else
                mov eax,LS_FAR16
            .endif
            mov ecx,opnd1
            mov [ecx].value,eax
        .else
            mov ecx,GetSymOfssize(eax)
            mov edx,opnd2
            mov eax,sym
            SizeFromMemtype([edx].mem_type, ecx, [eax].type)
            mov ecx,opnd1
            mov [ecx].value,eax
        .endif
    .endif
    mov eax,NOT_ERROR
    ret

type_op endp

OPATTR_CODELABEL equ 0x01
OPATTR_DATALABEL equ 0x02
OPATTR_IMMEDIATE equ 0x04
OPATTR_DIRECTMEM equ 0x08
OPATTR_REGISTER  equ 0x10
OPATTR_DEFINED   equ 0x20
OPATTR_SSREL     equ 0x40
OPATTR_EXTRNREF  equ 0x80
OPATTR_LANG_MASK equ 0x700


opattr_op proc uses esi edi ebx oper:int_t, opnd1:expr_t, opnd2:expr_t, sym:asym_t, name:string_t

    mov ecx,opnd1
    mov edx,opnd2
    xor eax,eax

    mov [ecx].kind,EXPR_CONST
    mov [ecx].sym,NULL
    mov [ecx].value,0
    mov [ecx].mem_type,MT_EMPTY
    and [ecx].flags,not E_IS_OPEATTR
    .return .if [edx].kind == EXPR_EMPTY

    mov ebx,[edx].sym
    .if [edx].kind == EXPR_ADDR
        mov al,[edx].mem_type
        and al,MT_SPECIAL_MASK
        .if ebx && [ebx].state != SYM_STACK && eax == MT_ADDRESS
            or [ecx].value,OPATTR_CODELABEL
        .endif
        IsOffset(edx)
        mov ecx,opnd1
        .if eax && ebx
            mov al,[ebx].mem_type
            and eax,MT_SPECIAL_MASK
            .if eax == MT_ADDRESS
                or [ecx].value,OPATTR_CODELABEL
            .endif
        .endif
        .if ebx && ( ( [ebx].mem_type == MT_TYPE || !( [edx].mem_type & MT_SPECIAL ) ) || \
            ( [edx].mem_type == MT_EMPTY && !( [ebx].mem_type & MT_SPECIAL ) ) )
            or [ecx].value,OPATTR_DATALABEL
        .endif
    .endif
    .if ( [edx].kind != EXPR_ERROR && [edx].flags & E_INDIRECT )
        or [ecx].value,OPATTR_DATALABEL
    .endif

    IsOffset(edx)
    mov cl,[edx].mem_type
    and ecx,MT_SPECIAL_MASK
    .if ( [edx].kind == EXPR_CONST || ( [edx].kind == EXPR_ADDR && !( [edx].flags & E_INDIRECT ) && \
          ( ( [edx].mem_type == MT_EMPTY && eax ) || [edx].mem_type == MT_EMPTY || ecx == MT_ADDRESS ) && \
          ( [ebx].state == SYM_INTERNAL || [ebx].state == SYM_EXTERNAL ) ) )

        mov ecx,opnd1
        or [ecx].value,OPATTR_IMMEDIATE
    .endif

    mov ecx,opnd1
    .if ( [edx].kind == EXPR_ADDR && !( [edx].flags & E_INDIRECT ) && \
          ( ( [edx].mem_type == MT_EMPTY && [edx].inst == EMPTY ) || [edx].mem_type == MT_TYPE || \
          !( [edx].mem_type & MT_SPECIAL ) || [edx].mem_type == MT_PTR ) && \
          ( ebx == NULL || [ebx].state == SYM_INTERNAL || [ebx].state == SYM_EXTERNAL ) )
        or [ecx].value,OPATTR_DIRECTMEM
    .endif
    .if ( [edx].kind == EXPR_REG && !( [edx].flags & E_INDIRECT ) )
        or [ecx].value,OPATTR_REGISTER
    .endif
    .if ( [edx].kind != EXPR_ERROR && [edx].kind != EXPR_FLOAT && ( ebx == NULL || [ebx].flag & S_ISDEFINED ) )
        or [ecx].value,OPATTR_DEFINED
    .endif

    assume eax:nothing
    mov eax,[edx].idx_reg
    .if eax == 0
        mov eax,[edx].base_reg
    .endif
    .if eax
        imul eax,[eax].asm_tok.tokval,special_item
    .endif
    .if ( ( ebx && [ebx].state == SYM_STACK ) || \
          ( [edx].flags & E_INDIRECT && eax && ( SpecialTable[eax].sflags & SFR_SSBASED ) ) )
        or [ecx].value,OPATTR_SSREL
    .endif
    .if ebx && [ebx].state == SYM_EXTERNAL
        or [ecx].value,OPATTR_EXTRNREF
    .endif
    .if oper == T_OPATTR
        .if ebx && [edx].kind != EXPR_ERROR
            movzx eax,[ebx].langtype
            shl eax,8
            or [ecx].value,eax
        .endif
    .endif
    mov eax,NOT_ERROR
    ret
opattr_op endp

short_op proc oper:int_t, opnd1:expr_t, opnd2:expr_t, sym:asym_t, name:string_t

    mov edx,opnd2
    .if ( [edx].kind != EXPR_ADDR || ( [edx].mem_type != MT_EMPTY && \
          [edx].mem_type != MT_NEAR && [edx].mem_type != MT_FAR ) )
        .return fnasmerr(2028)
    .endif
    TokenAssign(opnd1, edx)
    mov [ecx].inst,oper
    mov eax,NOT_ERROR
    ret
short_op endp

seg_op proc oper:int_t, opnd1:expr_t, opnd2:expr_t, sym:asym_t, name:string_t

    mov edx,opnd2
    mov eax,[edx].sym
    .if eax == NULL || [eax].asym.state == SYM_STACK || [edx].flags & E_IS_ABS
        .return fnasmerr(2094)
    .endif
    TokenAssign(opnd1, edx)
    mov [ecx].inst,oper
    .if [ecx].mbr
        mov [ecx].value,0
    .endif
    mov [ecx].mem_type,MT_EMPTY
    mov eax,NOT_ERROR
    ret

seg_op endp

offset_op proc oper:int_t, opnd1:expr_t, opnd2:expr_t, sym:asym_t, name:string_t

    mov edx,opnd2
    .if oper == T_OFFSET
        .if [edx].kind == EXPR_CONST
            TokenAssign(opnd1, edx)
            .return NOT_ERROR
        .endif
    .endif
    mov eax,sym
    .if ( ( eax && [eax].asym.state == SYM_GRP ) || [edx].inst == T_SEG )
        .return invalid_operand(opnd2, GetResWName(oper, NULL), name)
    .endif
    .if ( [edx].flags & E_IS_TYPE )
        mov [edx].value,0
    .endif
    TokenAssign(opnd1, edx)
    mov [ecx].inst,oper
    .if [edx].flags & E_INDIRECT
        .return invalid_operand(opnd2, GetResWName(oper, NULL), name)
    .endif
    mov [ecx].mem_type,MT_EMPTY
    mov eax,NOT_ERROR
    ret
offset_op endp

lowword_op proc oper:int_t, opnd1:expr_t, opnd2:expr_t, sym:asym_t, name:string_t
    TokenAssign(opnd1, opnd2)
    .if [edx].kind == EXPR_ADDR && [edx].inst != T_SEG
        mov [ecx].inst,T_LOWWORD
        mov [ecx].mem_type,MT_EMPTY
    .endif
    and [ecx].value,0xffff
    mov [ecx].hvalue,0
    mov eax,NOT_ERROR
    ret
lowword_op endp

highword_op proc oper:int_t, opnd1:expr_t, opnd2:expr_t, sym:asym_t, name:string_t
    TokenAssign(opnd1, opnd2)
    .if [edx].kind == EXPR_ADDR && [edx].inst != T_SEG
        mov [ecx].inst,T_HIGHWORD
        mov [ecx].mem_type,MT_EMPTY
    .endif
    mov eax,[ecx].value
    shr eax,16
    mov [ecx].value,eax
    mov [ecx].hvalue,0
    mov eax,NOT_ERROR
    ret
highword_op endp

low_op proc oper:int_t, opnd1:expr_t, opnd2:expr_t, sym:asym_t, name:string_t
    TokenAssign(opnd1, opnd2)
    .if [edx].kind == EXPR_ADDR && [edx].inst != T_SEG
        mov [ecx].inst,T_DOT_LOW
        mov [ecx].mem_type,MT_EMPTY
    .endif
    and [ecx].value,0xff
    mov [ecx].hvalue,0
    mov eax,NOT_ERROR
    ret
low_op endp

high_op proc oper:int_t, opnd1:expr_t, opnd2:expr_t, sym:asym_t, name:string_t
    TokenAssign(opnd1, opnd2)
    .if [edx].kind == EXPR_ADDR && [edx].inst != T_SEG
        mov [ecx].inst,T_DOT_HIGH
        mov [ecx].mem_type,MT_EMPTY
    .endif
    mov eax,[ecx].value
    shr eax,8
    and eax,0xff
    mov [ecx].value,eax
    mov [ecx].hvalue,0
    mov eax,NOT_ERROR
    ret
high_op endp

tofloat proc opnd1:expr_t, opnd2:expr_t, size:int_t

    mov ecx,opnd1
    mov edx,opnd2
    .if ModuleInfo.strict_masm_compat
        ConstError(ecx, edx)
        mov ecx,eax
        .return 1
    .endif
    mov [edx].kind,EXPR_CONST
    mov eax,[edx].float_tok
    .if eax
        xor ecx,ecx
        .if [edx].flags & E_NEGATIVE
            inc ecx
        .endif
        mov opnd1,ecx
        mov ecx,[eax].asm_tok.string_ptr
        mov [edx].float_tok,NULL
        atofloat(edx, ecx, size, opnd1, [eax].asm_tok.floattype)
        xor eax,eax
    .endif
    ret

tofloat endp

low32_op proc oper:int_t, opnd1:expr_t, opnd2:expr_t, sym:asym_t, name:string_t
    mov edx,opnd2
    .if [edx].kind == EXPR_FLOAT
        .return ecx .if tofloat(opnd1, edx, 8)
    .endif
    TokenAssign(opnd1, opnd2)
    mov [ecx].mem_type,MT_DWORD
    .if [edx].kind == EXPR_ADDR && [edx].inst != T_SEG
        mov [ecx].inst,T_LOW32
        mov [ecx].mem_type,MT_EMPTY
    .endif
    mov [ecx].hvalue,0
    mov eax,NOT_ERROR
    ret
low32_op endp

high32_op proc oper:int_t, opnd1:expr_t, opnd2:expr_t, sym:asym_t, name:string_t
    mov edx,opnd2
    .if [edx].kind == EXPR_FLOAT
        .return ecx .if tofloat(opnd1, edx, 8)
    .endif
    TokenAssign(opnd1, opnd2)
    mov [ecx].mem_type,MT_DWORD
    .if [edx].kind == EXPR_ADDR && [edx].inst != T_SEG
        mov [ecx].inst,T_HIGH32
        mov [ecx].mem_type,MT_EMPTY
    .endif
    mov eax,[ecx].hvalue
    mov [ecx].value,eax
    mov [ecx].hvalue,0
    mov eax,NOT_ERROR
    ret
high32_op endp

low64_op proc oper:int_t, opnd1:expr_t, opnd2:expr_t, sym:asym_t, name:string_t
    mov edx,opnd2
    .if [edx].kind == EXPR_FLOAT
        .return ecx .if tofloat(opnd1, edx, 16)
    .endif
    TokenAssign(opnd1, opnd2)
    mov [ecx].mem_type,MT_QWORD
    .if [edx].kind == EXPR_ADDR && [edx].inst != T_SEG
        mov [ecx].inst,T_LOW64
        mov [ecx].mem_type,MT_EMPTY
    .endif
    mov dword ptr [ecx].hlvalue,0
    mov dword ptr [ecx].hlvalue[4],0
    mov eax,NOT_ERROR
    ret
low64_op endp

high64_op proc oper:int_t, opnd1:expr_t, opnd2:expr_t, sym:asym_t, name:string_t
    mov edx,opnd2
    xor eax,eax
    .if [edx].kind == EXPR_FLOAT
        .return ecx .if tofloat(opnd1, edx, 16)
    .elseif [edx].flags & E_NEGATIVE && [edx+8] == eax && [edx+12] == eax
        dec eax
        mov [edx+8],eax
        mov [edx+12],eax
    .endif
    TokenAssign(opnd1, opnd2)
    mov [ecx].mem_type,MT_QWORD
    .if [edx].kind == EXPR_ADDR && [edx].inst != T_SEG
        mov [ecx].inst,T_HIGH64
        mov [ecx].mem_type,MT_EMPTY
    .endif
    mov eax,[ecx+8]
    mov edx,[ecx+12]
    mov [ecx],eax
    mov [ecx+4],edx
    xor eax,eax
    mov [ecx+8],eax
    mov [ecx+12],eax
    ret
high64_op endp

this_op proc oper:int_t, opnd1:expr_t, opnd2:expr_t, sym:asym_t, name:string_t
    mov edx,opnd2
    .return fnasmerr(2010) .if !( [edx].flags & E_IS_TYPE )
    .return fnasmerr(2034) .if CurrStruct
    .return asmerr(2034) .if ModuleInfo.currseg == NULL
    mov eax,thissym
    .if eax == NULL
        mov thissym,SymAlloc("")
        mov [eax].asym.state,SYM_INTERNAL
        or  [eax].asym.flag,S_ISDEFINED
    .endif
    mov ecx,opnd1
    mov edx,opnd2
    mov [ecx].kind,EXPR_ADDR
    mov [ecx].sym,eax
    mov ecx,[edx].type
    mov [eax].asym.type,ecx
    .if ecx
        mov [eax].asym.mem_type,MT_TYPE
    .else
        mov cl,[edx].mem_type
        mov [eax].asym.mem_type,cl
    .endif
    SetSymSegOfs(eax)
    mov eax,thissym
    mov ecx,opnd1
    mov al,[eax].asym.mem_type
    mov [ecx].mem_type,al
    mov eax,NOT_ERROR
    ret
this_op endp

    assume esi:nothing

wimask_op proc uses esi edi ebx oper:int_t, opnd1:expr_t, opnd2:expr_t, sym:asym_t, name:string_t
    mov ecx,opnd1
    mov edx,opnd2
    .if [edx].flags & E_IS_TYPE
        mov eax,[edx].type
        .if [eax].asym.typekind != TYPE_RECORD
            .return fnasmerr(2019)
        .endif
    .elseif [edx].kind == EXPR_CONST
        mov eax,[edx].mbr
    .else
        mov eax,[edx].sym
    .endif
    .if oper == T_DOT_MASK
        mov [ecx].value,0
        .if [edx].flags & E_IS_TYPE
            GetRecordMask(eax)
        .else
            mov ebx,eax
            xor eax,eax
            xor edx,edx
            mov ecx,[ebx]._offset
            mov edi,[ebx].total_size
            add edi,ecx
            .for ( : ecx < edi : ecx++ )
                mov esi,1
                .if ecx < 32
                    shl esi,cl
                    or  eax,esi
                .else
                    sub ecx,32
                    shl esi,cl
                    or  edx,esi
                    add ecx,32
                .endif
            .endf
        .endif
        mov ecx,opnd1
        mov [ecx].value,eax
        mov [ecx].hvalue,edx
    .else
        .if [edx].flags & E_IS_TYPE
            mov eax,[eax].esym.structinfo
            mov esi,[eax].struct_info.head
            .for ( : esi : esi = [esi].sfield.next )
                mov ebx,[esi].sfield.sym
                add [ecx].value,[ebx].total_size
            .endf
        .else
            mov [ecx].value,[eax].asym.total_size
        .endif
    .endif
    mov [ecx].kind,EXPR_CONST
    mov eax,NOT_ERROR
    ret

wimask_op endp

    .data
res macro token, function
    dd function
    endm
    align 8
unaryop label unaryop_t
include unaryop.h
undef res
    .code

    assume esi:expr_t
    assume edi:expr_t
    assume ecx:nothing
    assume edx:nothing

plus_op proc uses esi edi ebx opnd1:expr_t, opnd2:expr_t

    mov esi,opnd1
    mov edi,opnd2

    .if check_direct_reg( esi, edi ) == ERROR
        .return fnasmerr( 2032 )
    .endif
    .if [esi].kind == EXPR_REG
        mov [esi].kind,EXPR_ADDR
    .endif
    .if [edi].kind == EXPR_REG
       mov [edi].kind,EXPR_ADDR
    .endif
    .if [edi].override
        .if [esi].override
            mov ecx,[esi].override
            mov edx,[edi].override
            .if [ecx].asm_tok.token == [edx].asm_tok.token
                .return fnasmerr( 3013 )
            .endif
        .endif
        mov [esi].override,[edi].override
    .endif
    .if [esi].kind == EXPR_CONST && [edi].kind == EXPR_CONST
        add [esi].value,[edi].value
        adc [esi].hvalue,[edi].hvalue
    .elseif [esi].kind == EXPR_FLOAT && [edi].kind == EXPR_FLOAT
        .if [edi].float_tok
            mov ecx,[edi].float_tok
            xor edx,edx
            .if [edi].flags & E_NEGATIVE
                inc edx
            .endif
            atofloat(edi, [ecx].asm_tok.string_ptr, 16, edx, 0 )
        .endif
        __addq( esi, edi )
    .elseif( ( [esi].kind == EXPR_ADDR && [edi].kind == EXPR_ADDR ) )
        fix_struct_value(esi)
        fix_struct_value(edi)
        .return ERROR .if index_connect(esi, edi) == ERROR
        .if [edi].sym != NULL
            mov ebx,[esi].sym
            mov edx,[edi].sym
            .if ebx && [ebx].state != SYM_UNDEFINED && [edx].asym.state != SYM_UNDEFINED
                .return( fnasmerr( 2101 ) )
            .endif
            mov [esi].label_tok,[edi].label_tok
            mov [esi].sym,[edi].sym
            .if [esi].mem_type == MT_EMPTY
                mov [esi].mem_type,[edi].mem_type
            .endif
            .if [edi].inst != EMPTY
                mov [esi].inst,[edi].inst
            .endif
        .endif
        add [esi].value,[edi].value
        adc [esi].hvalue,[edi].hvalue
        .if [edi].type
            mov [esi].type,[edi].type
        .endif
    .elseif check_both(esi, edi, EXPR_CONST, EXPR_ADDR)
        .if [esi].kind == EXPR_CONST
            add [edi].value,[esi].value
            adc [edi].hvalue,[esi].hvalue
            .if [esi].flags & E_INDIRECT
                or [edi].flags,E_INDIRECT
            .endif
            .if [esi].flags & E_EXPLICIT
                or  [edi].flags,E_EXPLICIT
                mov [edi].mem_type,[esi].mem_type
            .elseif [edi].mem_type == MT_EMPTY
                mov [edi].mem_type,[esi].mem_type
            .endif
            .if [edi].mbr == NULL
                mov [edi].mbr,[esi].mbr
            .endif
            .if [edi].type
                mov [esi].type,[edi].type
            .endif
            TokenAssign(esi, edi)
        .else
            add [esi].value,[edi].value
            adc [esi].hvalue,[edi].hvalue
            .if [edi].mbr
                mov [esi].mbr,[edi].mbr
                mov [esi].mem_type,[edi].mem_type
            .elseif [esi].mem_type == MT_EMPTY && !( [edi].flags & E_IS_TYPE )
                mov [esi].mem_type,[edi].mem_type
            .endif
        .endif
        fix_struct_value(esi)
    .else
        .return ConstError(esi, edi)
    .endif
    mov eax,NOT_ERROR
    ret
plus_op endp

    assume ecx:expr_t
    assume edx:expr_t

minus_op proc fastcall uses ebx opnd1:expr_t, opnd2:expr_t

    .if check_direct_reg(ecx, edx) == ERROR
        .return fnasmerr(2032)
    .endif
    mov eax,[edx].sym
    .if !( [ecx].kind == EXPR_ADDR && [edx].kind == EXPR_ADDR && \
           eax && [eax].asym.state == SYM_UNDEFINED )
        xchg edx,ecx
        MakeConst(ecx)
        xchg edx,ecx
    .endif
    .if [ecx].kind == EXPR_CONST && [edx].kind == EXPR_CONST
        sub [ecx].value,[edx].value
        sbb [ecx].hvalue,[edx].hvalue
    .elseif [ecx].kind == EXPR_FLOAT && [edx].kind == EXPR_FLOAT
        .if [edx].float_tok
            push edx
            push ecx
            mov eax,[edx].float_tok
            xor ecx,ecx
            .if [edx].flags & E_NEGATIVE
                inc ecx
            .endif
            atofloat( edx, [eax].asm_tok.string_ptr, 16, ecx, 0 )
            pop ecx
            pop edx
        .endif
        __subq(ecx, edx)
    .elseif [ecx].kind == EXPR_ADDR && [edx].kind == EXPR_CONST
        sub [ecx].value,[edx].value
        sbb [ecx].hvalue,[edx].hvalue
        fix_struct_value(ecx)
    .elseif [ecx].kind == EXPR_ADDR && [edx].kind == EXPR_ADDR
        fix_struct_value(ecx)
        xchg edx,ecx
        fix_struct_value(ecx)
        xchg edx,ecx
        .if( [edx].flags & E_INDIRECT )
            .return fnasmerr( 2032 )
        .endif
        .if( [edx].label_tok == NULL )
            sub [ecx].value,[edx].value
            sbb [ecx].hvalue,[edx].hvalue
            .if( [edx].flags & E_INDIRECT )
                or [ecx].flags,E_INDIRECT
            .endif
        .else
            .if [ecx].label_tok == NULL || [ecx].sym == NULL || [edx].sym == NULL
                .return fnasmerr(2094)
            .endif
            mov ebx,[ecx].sym
            add [ecx].value,[ebx]._offset
            mov eax,[edx].sym
            .if Parse_Pass > PASS_1
                .if ( ( [eax].asym.state == SYM_EXTERNAL || [ebx].state == SYM_EXTERNAL ) \
                    && eax != [ecx].sym )
                    .return( fnasmerr(2018, [ebx].name ) )
                .endif
                .if ( [ebx]._segment != [eax].asym._segment )
                    .return( fnasmerr( 2025 ) )
                .endif
                mov eax,[edx].sym
            .endif
            mov [ecx].kind,EXPR_CONST
            .if ( [ebx].state == SYM_UNDEFINED || [eax].asym.state == SYM_UNDEFINED )
                mov [ecx].value,1
                .if ( [ebx].state != SYM_UNDEFINED )
                    mov [ecx].sym,eax
                    mov [ecx].label_tok,[edx].label_tok
                .endif
                mov [ecx].kind,EXPR_ADDR
            .else
                sub [ecx].value,[eax].asym._offset
                sbb [ecx].hvalue,0
                sub [ecx].value,[edx].value
                sbb [ecx].hvalue,[edx].hvalue
                mov [ecx].label_tok,NULL
                mov [ecx].sym,NULL
            .endif
            .if !( [ecx].flags & E_INDIRECT )
                .if [ecx].inst == T_OFFSET && [edx].inst == T_OFFSET
                    mov [ecx].inst,EMPTY
                .endif
            .else
                mov [ecx].kind,EXPR_ADDR
            .endif
            and [ecx].flags,not E_EXPLICIT
            mov [ecx].mem_type,MT_EMPTY
        .endif
    .elseif [ecx].kind == EXPR_REG && [edx].kind == EXPR_CONST
        .if [edx].flags & E_INDIRECT
            or [ecx].flags,E_INDIRECT
        .endif
        mov [ecx].kind,EXPR_ADDR
        push ecx
        push -1
        push -1
        push [edx].hvalue
        push [edx].value
        call __llmul
        pop ecx
        mov [ecx].value,eax
        mov [ecx].hvalue,edx
    .else
        .return ConstError( ecx, edx )
    .endif
    mov eax,NOT_ERROR
    ret

minus_op endp

struct_field_error proc fastcall opnd:expr_t

    .if [ecx].flags & E_IS_OPEATTR
        mov [ecx].kind,EXPR_ERROR
        .return NOT_ERROR
    .endif
    fnasmerr(2166)
    ret

struct_field_error endp

dot_op proc fastcall uses ebx opnd1:expr_t, opnd2:expr_t

    .if check_direct_reg(ecx, edx) == ERROR
        .return fnasmerr(2032)
    .endif
    .if [ecx].kind == EXPR_REG
        mov [ecx].kind,EXPR_ADDR
    .endif
    .if [edx].kind == EXPR_REG
        mov [edx].kind,EXPR_ADDR
    .endif
    mov eax,[edx].sym
    .if eax && [eax].asym.state == SYM_UNDEFINED && Parse_Pass == PASS_1
        mov eax,nullstruct
        .if !eax
            push ecx
            push edx
            mov nullstruct,CreateTypeSymbol( NULL, "", 0 )
            pop edx
            pop ecx
        .endif
        mov [edx].type,eax
        or  [edx].flags,E_IS_TYPE
        mov [edx].sym,NULL
        mov [edx].kind,EXPR_CONST
    .endif
    .if [ecx].kind == EXPR_ADDR && [edx].kind == EXPR_ADDR
        .if [edx].mbr == NULL && !ModuleInfo.oldstructs
            .return struct_field_error( ecx )
        .endif
        .return .if index_connect( ecx, edx ) == ERROR
        mov eax,[edx].sym
        .if eax
            mov ebx,[ecx].sym
            .if ebx && [ebx].state != SYM_UNDEFINED && [eax].asym.state != SYM_UNDEFINED
                .return( fnasmerr( 2101 ) )
            .endif
            mov [ecx].label_tok,[edx].label_tok
            mov [ecx].sym,[edx].sym
        .endif
        mov eax,[edx].mbr
        .if eax
            mov [ecx].mbr,eax
        .endif
        add [ecx].value,[edx].value
        .if !( [ecx].flags & E_EXPLICIT )
            mov [ecx].mem_type,[edx].mem_type
        .endif
        mov eax,[edx].type
        .if eax
            mov [ecx].type,eax
        .endif
    .elseif [ecx].kind == EXPR_CONST && [edx].kind == EXPR_ADDR
        .if [ecx].flags & E_IS_TYPE && [ecx].type
            and [edx].flags,not E_ASSUMECHECK
            mov [ecx].value,0
            mov [ecx].hvalue,0
        .endif
        .if ( ( !ModuleInfo.oldstructs ) && ( !( [ecx].flags & E_IS_TYPE ) && [ecx].mbr == NULL ) )
            .return struct_field_error(ecx)
        .endif
        mov ebx,[ecx].mbr
        .if ebx && [ebx].state == SYM_TYPE
            mov [ecx].value,[ebx]._offset
            mov [ecx].hvalue,0
        .endif
        .if [ecx].flags & E_INDIRECT
            or [edx].flags,E_INDIRECT
        .endif
        add [edx].value,[ecx].value
        adc [edx].hvalue,[ecx].hvalue
        .if [edx].mbr
            mov [ecx].type,[edx].type
        .endif
        TokenAssign(ecx, edx)
    .elseif( [ecx].kind == EXPR_ADDR && [edx].kind == EXPR_CONST )
        .if ( !ModuleInfo.oldstructs && ( [edx].type == NULL || \
            !( [edx].flags & E_IS_TYPE ) ) && [edx].mbr == NULL )
            .return struct_field_error(ecx)
        .endif
        .if ( [edx].flags & E_IS_TYPE && [edx].type )
            and [ecx].flags,not E_ASSUMECHECK
            ;; v2.37: adjust for type's size only (japheth)
            mov ebx,[edx].type
            sub [edx].value,[ebx].total_size
            sbb [edx].hvalue,0
        .endif
        mov ebx,[edx].mbr
        .if ebx && [ebx].state == SYM_TYPE
            mov [edx].value,[ebx]._offset
            mov [edx].hvalue,0
        .endif
        add [ecx].value,[edx].value
        adc [ecx].hvalue,[edx].hvalue
        mov [ecx].mem_type,[edx].mem_type
        .if ebx
            mov [ecx].mbr,ebx
        .endif
        mov [ecx].type,[edx].type
    .elseif [ecx].kind == EXPR_CONST && [edx].kind == EXPR_CONST
        .if [edx].mbr == NULL && !ModuleInfo.oldstructs
            .return struct_field_error(ecx)
        .endif
        .if [ecx].type != NULL
            .if [ecx].mbr != NULL
                add [ecx].value,[edx].value
                adc [ecx].hvalue,[edx].hvalue
            .else
                mov [ecx].value,[edx].value
                mov [ecx].hvalue,[edx].hvalue
            .endif
            mov [ecx].mbr,[edx].mbr
            mov [ecx].mem_type,[edx].mem_type
            and [ecx].flags,not E_IS_TYPE
            .if [edx].flags & E_IS_TYPE
                or [ecx].flags,E_IS_TYPE
            .endif
            .if [ecx].type != [edx].type
                mov [ecx].type,[edx].type
            .else
                mov [ecx].type,NULL
            .endif
        .else
            add [ecx].value,[edx].value
            adc [ecx].hvalue,[edx].hvalue
            mov [ecx].mbr,[edx].mbr
            mov [ecx].mem_type,[edx].mem_type
        .endif
    .else
        .return struct_field_error(ecx)
    .endif
    mov eax,NOT_ERROR
    ret

dot_op endp

colon_op proc fastcall uses ebx opnd1:expr_t, opnd2:expr_t

    mov eax,[edx].override
    .if eax
        .if ( ( [ecx].kind == EXPR_REG && [eax].asm_tok.token == T_REG ) || \
            ( [ecx].kind == EXPR_ADDR && [eax].asm_tok.token == T_ID ) )
            .return( fnasmerr( 3013 ) )
        .endif
    .endif
    .switch [edx].kind
    .case EXPR_REG
        .if !( [edx].flags & E_INDIRECT )
            .return fnasmerr( 2032 )
        .endif
        .endc
    .case EXPR_FLOAT
        .return fnasmerr( 2050 )
    .endsw
    .if ( [ecx].kind == EXPR_REG )
        .if ( [ecx].idx_reg != NULL )
            .return( fnasmerr( 2032 ) )
        .endif
        mov eax,[ecx].base_reg
        imul eax,[eax].asm_tok.tokval,special_item
        .if !( SpecialTable[eax].value & OP_SR )
            .return( fnasmerr( 2096 ) )
        .endif
        mov [edx].override,[ecx].base_reg
        .if [ecx].flags & E_INDIRECT
            or [edx].flags,E_INDIRECT
        .endif
        .if [edx].kind == EXPR_CONST
            mov [edx].kind,EXPR_ADDR
        .endif
        .if [ecx].flags & E_EXPLICIT
            or  [edx].flags,E_EXPLICIT
            mov [edx].mem_type,[ecx].mem_type
            mov [edx].Ofssize,[ecx].Ofssize
        .endif
        TokenAssign( ecx, edx )
        .if [edx].type
            mov [ecx].type,[edx].type
        .endif
    .elseif ( [ecx].kind == EXPR_ADDR && [ecx].override == NULL && [ecx].inst == EMPTY && \
              [ecx].value == 0 && [ecx].sym && [ecx].base_reg == NULL && [ecx].idx_reg == NULL )

        mov eax,[ecx].sym
        .if [eax].asym.state == SYM_GRP || [eax].asym.state == SYM_SEG
            mov [edx].kind,EXPR_ADDR
            mov [edx].override,[ecx].label_tok
            .if [ecx].flags & E_INDIRECT
                or [edx].flags,E_INDIRECT
            .endif
            .if [ecx].flags & E_EXPLICIT
                or  [edx].flags,E_EXPLICIT
                mov [edx].mem_type,[ecx].mem_type
                mov [edx].Ofssize,[ecx].Ofssize
            .endif
            TokenAssign( ecx, edx )
            mov [ecx].type,[edx].type
        .elseif Parse_Pass > PASS_1 || [eax].asym.state != SYM_UNDEFINED
            .return fnasmerr( 2096 )
        .endif
    .else
        .return fnasmerr( 2096 )
    .endif
    mov eax,NOT_ERROR
    ret

colon_op endp

positive_op proc fastcall opnd1:expr_t, opnd2:expr_t

    xchg edx,ecx
    MakeConst(ecx)
    xchg edx,ecx
    .if [edx].kind == EXPR_CONST
        mov [ecx].kind,EXPR_CONST
        mov [ecx].value,[edx].value
        mov [ecx].hvalue,[edx].hvalue
        mov eax,dword ptr [edx].hlvalue
        mov dword ptr [ecx].hlvalue,eax
        mov eax,dword ptr [edx].hlvalue[4]
        mov dword ptr [ecx].hlvalue[4],eax
    .elseif [edx].kind == EXPR_FLOAT
        mov [ecx].kind,EXPR_FLOAT
        mov [ecx].float_tok,[edx].float_tok
        and [ecx].flags,not E_NEGATIVE
        .if [edx].flags & E_NEGATIVE
            or [ecx].flags,E_NEGATIVE
        .endif
    .else
        .return( fnasmerr( 2026 ) )
    .endif
    mov eax,NOT_ERROR
    ret

positive_op endp

negative_op proc fastcall uses ebx opnd1:expr_t, opnd2:expr_t

    xchg edx,ecx
    MakeConst(ecx)
    xchg edx,ecx
    .if [edx].kind == EXPR_CONST
        mov [ecx].kind,EXPR_CONST
        mov eax,[edx].value
        mov ebx,[edx].hvalue
        neg eax
        adc ebx,0
        neg ebx
        mov [ecx].value,eax
        mov [ecx].hvalue,ebx
        sbb eax,eax
        mov ebx,dword ptr [edx].hlvalue[4]
        .if dword ptr [edx].hlvalue || ebx
            bt  eax,0
            mov eax,dword ptr [edx].hlvalue
            adc eax,0
            neg eax
            adc ebx,0
            neg ebx
            mov dword ptr [ecx].hlvalue,eax
            mov dword ptr [ecx].hlvalue[4],ebx
        .endif
        .if [edx].flags & E_NEGATIVE
            and [ecx].flags,not E_NEGATIVE
        .else
            or [ecx].flags,E_NEGATIVE
        .endif
    .elseif [edx].kind == EXPR_FLOAT
        mov [ecx].kind,EXPR_FLOAT
        mov [ecx].float_tok,[edx].float_tok
        .if [edx].flags & E_NEGATIVE
            and [ecx].flags,not E_NEGATIVE
        .else
            or [ecx].flags,E_NEGATIVE
        .endif
    .else
        .return fnasmerr( 2026 )
    .endif
    mov eax,NOT_ERROR
    ret

negative_op endp

CheckAssume proc fastcall uses esi ebx opnd:expr_t

    mov esi,ecx
    .if [esi].flags & E_EXPLICIT
        mov ebx,[esi].type
        .if [esi].type && [ebx].mem_type == MT_PTR
            .if [ebx].is_ptr == 1
                mov [esi].mem_type,[ebx].ptr_memtype
                mov [esi].type,[ebx].target_type
                .return
            .endif
        .endif
    .endif

    xor ebx,ebx
    .if [esi].idx_reg
        mov eax,[esi].idx_reg
        mov ebx,GetStdAssumeEx( [eax].asm_tok.bytval )
    .endif
    .if !ebx && [esi].base_reg
        mov eax,[esi].base_reg
        mov ebx,GetStdAssumeEx( [eax].asm_tok.bytval )
    .endif

    .if ebx
        .if [ebx].mem_type == MT_TYPE
            mov [esi].type,[ebx].type
        .elseif [ebx].is_ptr == 1
            mov [esi].type,[ebx].target_type
            .if [ebx].target_type
                mov ebx,[ebx].target_type
                mov [esi].mem_type,[ebx].mem_type
            .else
                mov [esi].mem_type,[ebx].ptr_memtype
            .endif
        .endif
    .endif
    ret

CheckAssume endp

check_streg proc fastcall opnd1:expr_t, opnd2:expr_t

    .if [ecx].scale > 0
        .return( fnasmerr( 2032 ) )
    .endif
    inc [ecx].scale
    .if [edx].kind != EXPR_CONST
        .return( fnasmerr( 2032 ) )
    .endif
    mov [ecx].st_idx,[edx].value
    mov eax,NOT_ERROR
    ret

check_streg endp

    assume esi:asym_t
    assume edi:asym_t

cmp_types proc uses esi edi ebx opnd1:expr_t, opnd2:expr_t, trueval:int_t

    mov ecx,opnd1
    mov edx,opnd2
    mov esi,[ecx].type
    mov edi,[edx].type

    .if ( [ecx].mem_type == MT_PTR && [edx].mem_type == MT_PTR )

        .if !esi
            mov eax,[ecx].type_tok
            mov esi,SymFind([eax].asm_tok.string_ptr)
            mov edx,opnd2
        .endif
        .if !edi
            mov eax,[edx].type_tok
            mov edi,SymFind([eax].asm_tok.string_ptr)
        .endif
        .if ( [esi].is_ptr == [edi].is_ptr && \
              [esi].ptr_memtype == [edi].ptr_memtype && \
              [esi].target_type == [edi].target_type )
            mov eax,trueval
        .else
            mov eax,trueval
            not eax
        .endif
        cdq
        mov ecx,opnd1
        mov [ecx].value,eax
        mov [ecx].hvalue,edx
    .else
        .if esi && [esi].typekind == TYPE_TYPEDEF && [esi].is_ptr == 0
            mov [ecx].type,NULL
        .endif
        .if edi && [edi].typekind == TYPE_TYPEDEF && [edi].is_ptr == 0
            mov [edx].type,NULL
        .endif
        .if ( [ecx].mem_type == [edx].mem_type && [ecx].type == [edx].type )
            mov eax,trueval
        .else
            mov eax,trueval
            not eax
        .endif
        cdq
        mov [ecx].value,eax
        mov [ecx].hvalue,edx
    .endif
    ret

cmp_types endp

    assume ebx:tok_t
    assume esi:expr_t
    assume edi:expr_t

calculate proc uses esi edi ebx opnd1:expr_t, opnd2:expr_t, oper:tok_t

  local sym:asym_t

    mov esi,opnd1
    mov edi,opnd2
    mov ebx,oper

    mov [esi].quoted_string,NULL
    .if ( ( dword ptr [edi].hlvalue || dword ptr [edi].hlvalue[4] ) && [edi].mem_type != MT_REAL16 )
        .if ( !( [ebx].token == T_UNARY_OPERATOR && [edi].kind == EXPR_CONST && \
                ModuleInfo.Ofssize == USE64 ) )

            .if ( !( [edi].flags & E_IS_OPEATTR || ( ( [ebx].token == '+' || \
                [ebx].token == '-' ) && [ebx].specval == 0 ) ) )
                .return( fnasmerr( 2084, [edi].hlvalue, [edi].value64 ) )
            .endif
        .endif
    .endif
    movzx eax,[ebx].token
    .switch eax
    .case T_OP_SQ_BRACKET
        .if [edi].flags & E_ASSUMECHECK
            and [edi].flags,not E_ASSUMECHECK
            .if [esi].sym == NULL
                CheckAssume(edi)
            .endif
        .endif
        .if [esi].kind == EXPR_EMPTY
            TokenAssign( esi, edi )
            mov [esi].type,[edi].type
            .if [esi].flags & E_IS_TYPE && [esi].kind == EXPR_CONST
                and [esi].flags,not E_IS_TYPE
            .endif
            .endc
        .endif
        .if ( [esi].flags & E_IS_TYPE && [esi].type == NULL && \
            ( [edi].kind == EXPR_ADDR || [edi].kind == EXPR_REG ) )
            .return( fnasmerr( 2009 ) )
        .endif
        mov eax,[esi].base_reg
        .if eax && [eax].asm_tok.tokval == T_ST
            .return( check_streg( esi, edi ) )
        .endif
        .return( plus_op( esi, edi ) )
    .case T_OP_BRACKET
        .if [esi].kind == EXPR_EMPTY
            TokenAssign( esi, edi )
            mov [esi].type,[edi].type
            .endc
        .endif
        .if [esi].flags & E_IS_TYPE && [edi].kind == EXPR_ADDR
            .return( fnasmerr( 2009 ) )
        .endif
        mov eax,[esi].base_reg
        .if [esi].base_reg && [eax].asm_tok.tokval == T_ST
            .return( check_streg( esi, edi ) )
        .endif
        .return( plus_op( esi, edi ) )
    .case '+'
        .if [ebx].specval == 0
            .return( positive_op( esi, edi ) )
        .endif
        .return( plus_op( esi, edi ) )
    .case '-'
        .if [ebx].specval == 0
            .return( negative_op( esi, edi ) )
        .endif
        .return( minus_op( esi, edi ) )
    .case T_DOT
        .return( dot_op( esi, edi ) )
    .case T_COLON
        .return( colon_op( esi, edi ) )
    .case '*'
        MakeConst(esi)
        MakeConst(edi)
        .if [esi].kind == EXPR_CONST && [edi].kind == EXPR_CONST
            push [esi].hvalue
            push [esi].value
            push [edi].hvalue
            push [edi].value
            call __llmul
            mov [esi].value,eax
            mov [esi].hvalue,edx
        .elseif check_both( esi, edi, EXPR_REG, EXPR_CONST )
            .if check_direct_reg( esi, edi ) == ERROR
                .return fnasmerr( 2032 )
            .endif
            .if [edi].kind == EXPR_REG
                mov [esi].idx_reg,[edi].base_reg
                mov [esi].scale,[esi].value
                mov [esi].value,0
            .else
                mov [esi].idx_reg,[esi].base_reg
                mov [esi].scale,[edi].value
            .endif
            .if [esi].scale == 0
                .return( fnasmerr( 2083 ) )
            .endif
            mov [esi].base_reg,NULL
            or  [esi].flags,E_INDIRECT
            mov [esi].kind,EXPR_ADDR
        .elseif [esi].kind == EXPR_FLOAT && [edi].kind == EXPR_FLOAT
            .if [edi].float_tok
                xor ecx,ecx
                test [edi].flags,E_NEGATIVE
                setnz cl
                mov eax,[edi].float_tok
                atofloat( edi, [eax].asm_tok.string_ptr, 16, ecx, 0)
            .endif
            __mulq(esi, edi)
        .else
            .return( ConstError( esi, edi ) )
        .endif
        .endc
    .case '/'
        .if ( ( [esi].kind == EXPR_FLOAT && [edi].kind == EXPR_FLOAT ) )
            .if [edi].float_tok
                xor ecx,ecx
                test [edi].flags,E_NEGATIVE
                setnz cl
                mov eax,[edi].float_tok
                atofloat( edi, [eax].asm_tok.string_ptr, 16, ecx, 0)
            .endif
            __divq(esi, edi)
            .endc
        .endif
        MakeConst( esi )
        MakeConst( edi )
        .if( !( [esi].kind == EXPR_CONST && [edi].kind == EXPR_CONST ) )
            .return( ConstError( esi, edi ) )
        .endif
        .if [edi].value == 0 && [edi].hvalue == 0
            .return( fnasmerr( 2169 ) )
        .endif
        push [edi].hvalue
        push [edi].value
        push [esi].hvalue
        push [esi].value
        call __lldiv
        mov [esi].value,eax
        mov [esi].hvalue,edx
        .endc
    .case T_BINARY_OPERATOR
        .if [ebx].tokval == T_PTR
            .if !( [esi].flags & E_IS_TYPE )
                mov eax,[esi].sym
                .if eax && [eax].asym.state == SYM_UNDEFINED
                    CreateTypeSymbol( eax, NULL, 1 )
                    mov [esi].type,[esi].sym
                    mov [esi].sym,NULL
                    or  [esi].flags,E_IS_TYPE
                .else
                    .return( fnasmerr( 2010 ) )
                .endif
            .endif
            or [edi].flags,E_EXPLICIT
            .if ( [edi].kind == EXPR_REG && ( !( [edi].flags & E_INDIRECT ) || [edi].flags & E_ASSUMECHECK ) )
                mov eax,[edi].base_reg
                mov ecx,[eax].asm_tok.tokval
                imul eax,ecx,special_item
                .if ( SpecialTable[eax].value & OP_SR )
                    .if [esi].value != 2 && [esi].value != 4
                        .return( fnasmerr( 2032 ) )
                    .endif
                .elseif ( [esi].value != SizeFromRegister( ecx ) )
                    .return( fnasmerr( 2032 ) )
                .endif
            .elseif [edi].kind == EXPR_FLOAT
                .if !( [esi].mem_type & MT_FLOAT )
                    .return( fnasmerr( 2050 ) )
                .endif
            .endif
            mov [edi].mem_type,[esi].mem_type
            mov [edi].Ofssize,[esi].Ofssize
            .if [edi].flags & E_IS_TYPE
                mov [edi].value,[esi].value
            .endif
            .if [esi].override != NULL
                .if [edi].override == NULL
                    mov [edi].override,[esi].override
                .endif
                mov [edi].kind,EXPR_ADDR
            .endif
            TokenAssign( esi, edi )
            .endc
        .endif
        MakeConst( esi )
        MakeConst( edi )
        .if ( ( [esi].kind == EXPR_CONST && [edi].kind == EXPR_CONST ) )
        .elseif ( [ebx].precedence == 10 && [esi].kind != EXPR_CONST )
            .if ( [esi].kind == EXPR_ADDR && !( [esi].flags & E_INDIRECT ) && [esi].sym )
                .if ( [edi].kind == EXPR_ADDR && !( [edi].flags & E_INDIRECT ) && [edi].sym )
                    .return .if MakeConst2( esi, edi ) == ERROR
                .else
                    .return( fnasmerr( 2094 ) )
                .endif
            .else
                .return( fnasmerr( 2095 ) )
            .endif
        .else
            .return( ConstError( esi, edi ) )
        .endif
        .switch [ebx].tokval
        .case T_EQ
            .if ( [esi].flags & E_IS_TYPE && [edi].flags & E_IS_TYPE )
                cmp_types( esi, edi, -1 )
            .else
                xor edx,edx
                .if [esi].value == [edi].value && [esi].hvalue == [edi].hvalue
                    dec edx
                .endif
                mov [esi].value,edx
                mov [esi].hvalue,edx
            .endif
            .endc
        .case T_NE
            .if ( [esi].flags & E_IS_TYPE && [edi].flags & E_IS_TYPE )
                cmp_types( esi, edi, 0 )
            .else
                xor edx,edx
                .if [esi].value != [edi].value || [esi].hvalue != [edi].hvalue
                    dec edx
                .endif
                mov [esi].value,edx
                mov [esi].hvalue,edx
            .endif
            .endc
        .case T_LT
            xor edx,edx
            .if [esi].hvalue < [edi].hvalue
                dec edx
            .elseif ZERO?
                cmp [esi].value,[edi].value
                .ifb
                    dec edx
                .endif
            .endif
            mov [esi].value,edx
            mov [esi].hvalue,edx
            .endc
        .case T_LE
            xor edx,edx
            .if [esi].hvalue < [edi].hvalue
                dec edx
            .elseif ZERO?
                cmp [esi].value,[edi].value
                .ifna
                    dec edx
                .endif
            .endif
            mov [esi].value,edx
            mov [esi].hvalue,edx
            .endc
        .case T_GT
            xor edx,edx
            .if [esi].hvalue > [edi].hvalue
                dec edx
            .elseif ZERO?
                cmp [esi].value,[edi].value
                .ifa
                    dec edx
                .endif
            .endif
            mov [esi].value,edx
            mov [esi].hvalue,edx
            .endc
        .case T_GE
            xor edx,edx
            .if [esi].hvalue > [edi].hvalue
                dec edx
            .elseif ZERO?
                cmp [esi].value,[edi].value
                .ifnb
                    dec edx
                .endif
            .endif
            mov [esi].value,edx
            mov [esi].hvalue,edx
            .endc
        .case T_MOD
            .if [edi].value == 0 && [edi].hvalue == 0
                .return( fnasmerr( 2169 ) )
            .else
                push [edi].hvalue
                push [edi].value
                push [esi].hvalue
                push [esi].value
                call _allrem
                mov [esi].value,eax
                mov [esi].hvalue,edx
            .endif
            .endc
        .case T_SHL
            .if [edi].value < 0
                fnasmerr( 2092 )
            .elseif [edi].value >= 8*8
                mov [esi].value,0
                mov [esi].hvalue,0
            .else
                mov ecx,[edi].value
                mov eax,[esi].value
                mov edx,[esi].hvalue
                .if cl < 32
                    shld edx,eax,cl
                    shl eax,cl
                .else
                    and ecx,31
                    mov edx,eax
                    xor eax,eax
                    shl edx,cl
                .endif
                mov [esi].value,eax
                mov [esi].hvalue,edx
            .endif
            .if ModuleInfo.m510
                mov [esi].hvalue,0
                mov dword ptr [esi].hlvalue,0
                mov dword ptr [esi].hlvalue[4],0
            .endif
            .endc
        .case T_SHR
            .if [edi].value < 0
                fnasmerr( 2092 )
            .elseif [edi].value >= 8*8
                mov [esi].value,0
                mov [esi].hvalue,0
            .else
                mov ecx,[edi].value
                mov eax,[esi].value
                mov edx,[esi].hvalue
                .if eax == -1 && ModuleInfo.Ofssize == USE32
                    xor edx,edx
                .endif
                .if ecx > 63
                    xor eax,eax
                    xor edx,edx
                .elseif ecx < 32
                    shrd eax,edx,cl
                    shr edx,cl
                .else
                    mov eax,edx
                    xor edx,edx
                    and cl,32-1
                    shr eax,cl
                .endif
                mov [esi].value,eax
                mov [esi].hvalue,edx
            .endif
            .endc
        .case T_AND
            and [esi].value,[edi].value
            and [esi].hvalue,[edi].hvalue
            .endc
        .case T_OR
            or [esi].value,[edi].value
            or [esi].hvalue,[edi].hvalue
            .endc
        .case T_XOR
            xor [esi].value,[edi].value
            xor [esi].hvalue,[edi].hvalue
            .endc
        .endsw
        .endc
    .case T_UNARY_OPERATOR
        .if [ebx].tokval == T_NOT
            MakeConst(edi)
            .if [edi].kind != EXPR_CONST
                .return fnasmerr(2026)
            .endif
            TokenAssign(esi, edi)
            not [esi].value
            not [esi].hvalue
            .endc
        .endif
        imul eax,[ebx].tokval,special_item
        mov ecx,SpecialTable[eax].value
        mov eax,[edi].sym
        .if [edi].mbr != NULL
            mov eax,[edi].mbr
        .endif
        mov sym,eax
        push ecx
        .if [edi].inst != EMPTY
            strlen([ebx].string_ptr)
            inc eax
            add eax,[ebx].tokpos
        .elseif eax
            mov eax,[eax].asym.name
        .elseif [edi].base_reg != NULL && !( [edi].flags & E_INDIRECT )
            mov eax,[edi].base_reg
            mov eax,[eax].asm_tok.string_ptr
        .else
            strlen([ebx].string_ptr)
            inc eax
            add eax,[ebx].tokpos
        .endif
        mov edx,eax
        pop ecx

        .switch [edi].kind

        .case EXPR_CONST
            mov eax,[edi].mbr
            .if eax && [eax].asym.state != SYM_TYPE
                .if [eax].asym.mem_type == MT_BITS
                    .if !( ecx & AT_BF )
                        .return( invalid_operand( edi, [ebx].string_ptr, edx ) )
                    .endif
                .else
                    .if !( ecx & AT_FIELD )
                        .return( invalid_operand( edi, [ebx].string_ptr, edx ) )
                    .endif
                .endif
            .elseif [edi].flags & E_IS_TYPE
                .if !( ecx & AT_TYPE )
                    .return invalid_operand( edi, [ebx].string_ptr, edx )
                .endif
            .else
                .if !( ecx & AT_NUM )
                    .if [edi].flags & E_IS_OPEATTR
                        .return ERROR
                    .endif
                    .if ecx == 2
                        .return fnasmerr( 2094 )
                    .endif
                    .return fnasmerr( 2009 )
                .endif
            .endif
            .endc

        .case EXPR_ADDR
            .if ( [edi].flags & E_INDIRECT && [edi].sym == NULL )
                .if !( ecx & AT_IND )
                    .return invalid_operand( edi, [ebx].string_ptr, edx )
                .endif
            .else
                .if !( ecx & AT_LABEL )
                    .return ERROR .if [edi].flags & E_IS_OPEATTR
                    .if ( [ebx].tokval == T_HIGHWORD && [edi].flags != 4 )
                        .return fnasmerr( 2105 )
                    .endif
                    .if [edi].flags == 4
                        .return fnasmerr( 2026 )
                    .else
                        .return fnasmerr( 2009 )
                    .endif
                .endif
            .endif
            .endc

        .case EXPR_REG
            .if !( ecx & AT_REG )
                .if !( [edi].flags & E_IS_OPEATTR )
                    .if ecx == 2
                        .return fnasmerr( 2094 )
                    .endif
                    .if ecx == 0x33
                        .if [edi].flags & E_INDIRECT
                           .return fnasmerr( 2098 )
                        .else
                           .return fnasmerr( 2032 )
                        .endif
                    .endif
                    .if ecx & 0x20
                        .return fnasmerr( 2105 )
                    .endif
                    .if [edi].flags & E_INDIRECT
                        .return fnasmerr( 2081 )
                    .else
                        .return fnasmerr( 2009 )
                    .endif
                .else
                    .return ERROR
                .endif
            .endif
            .endc
        .case EXPR_FLOAT
            .if !( ecx & AT_FLOAT )
                .return fnasmerr( 2050 )
            .endif
            .endc
        .endsw
        imul eax,[ebx].tokval,special_item
        mov eax,SpecialTable[eax].sflags
        mov eax,unaryop[eax*4]
        assume eax:unaryop_t
        eax( [ebx].tokval, esi, edi, sym, edx )
        assume eax:nothing
        .return
    .default
        .return fnasmerr( 2008, [ebx].string_ptr )
    .endsw
    mov eax,NOT_ERROR
    ret
calculate endp

PrepareOp proc opnd:expr_t, old:expr_t, oper:tok_t

    mov ecx,opnd
    mov edx,old
    mov eax,oper

    and [ecx].flags,not E_IS_OPEATTR
    .if [edx].flags & E_IS_OPEATTR
        or [ecx].flags,E_IS_OPEATTR
    .endif
    .switch [eax].asm_tok.token
    .case T_DOT
        mov eax,[edx].sym
        .if [edx].type
            mov [ecx].type,[edx].type
            or  [ecx].flags,E_IS_DOT
        .elseif ( !ModuleInfo.oldstructs && eax && [eax].asym.state == SYM_UNDEFINED )
            mov [ecx].type,NULL
            or  [ecx].flags,E_IS_DOT
        .endif
        .endc
    .case T_UNARY_OPERATOR
        .switch [eax].asm_tok.tokval
        .case T_OPATTR
        .case T_DOT_TYPE
            or [ecx].flags,E_IS_OPEATTR
            .endc
        .endsw
        .endc
    .endsw
    ret

PrepareOp endp

OperErr proc i:int_t, tokenarray:tok_t

    mov eax,i
    shl eax,4
    add eax,tokenarray
    .if [eax].asm_tok.token <= T_BAD_NUM
        fnasmerr(2206)
    .else
        fnasmerr(2008, [eax].asm_tok.string_ptr)
    .endif
    ret

OperErr endp

    assume ecx:nothing
    assume edx:nothing
    assume esi:tok_t

evaluate proc uses esi edi ebx opnd1:expr_t, i:ptr int_t, tokenarray:tok_t, _end:int_t, flags:byte

  local rc:int_t
  local opnd2:expr
  local exp_token:int_t
  local last:int_t

    mov rc,NOT_ERROR
    mov edi,opnd1
    mov eax,i
    mov ebx,[eax]
    shl ebx,4
    add ebx,tokenarray

    mov eax,_end
    shl eax,4
    add eax,tokenarray
    mov last,eax

    .if ( [edi].kind == EXPR_EMPTY &&  !( [ebx].token == T_OP_BRACKET || \
          [ebx].token == T_OP_SQ_BRACKET || [ebx].token == '+' || \
          [ebx].token == '-' || [ebx].token == T_UNARY_OPERATOR ) )
        mov rc,get_operand( edi, i, tokenarray, flags )
        mov eax,i
        mov ebx,[eax]
        shl ebx,4
        add ebx,tokenarray
    .endif

    .while ( rc == NOT_ERROR && ebx < last && !( [ebx].token == T_CL_BRACKET ) && \
            !( [ebx].token == T_CL_SQ_BRACKET ) )

        mov esi,ebx

        .if ( [edi].kind != EXPR_EMPTY )

            movzx eax,[esi].token

            .if ( eax == '+' || eax == '-' )
                mov [esi].specval,1
            .elseif( !( eax >= T_OP_BRACKET || eax == T_UNARY_OPERATOR || \
                eax == T_BINARY_OPERATOR ) || eax == T_UNARY_OPERATOR )

                ;; v2.26 - added for {k1}{z}..
                .if ( eax == T_STRING && [esi].string_delim == '{' )
                    or  [esi].hll_flags,T_EVEX_OPT
                    mov edx,i
                    inc dword ptr [edx]
                    add ebx,16
                    .continue
                .else
                    mov rc,ERROR
                    .if !( [edi].flags & E_IS_OPEATTR )
                        sub esi,tokenarray
                        shr esi,4
                        OperErr( esi, tokenarray )
                    .endif
                    .break
                .endif
            .endif
            .if ( [edi].kind == EXPR_FLOAT && [edi].mem_type != MT_REAL16 )
                .if ( eax == '*' || eax == '/' || [esi].specval == 1 )
                    mov [edi].mem_type,MT_REAL16
                    xor ecx,ecx
                    test [edi].flags,E_NEGATIVE
                    setnz cl
                    mov eax,[edi].float_tok
                    atofloat( edi, [eax].asm_tok.string_ptr, 16, ecx, 0 )
                .endif
            .endif
        .endif
        mov edx,i
        inc dword ptr [edx]
        add ebx,16
        init_expr( &opnd2 )
        PrepareOp( &opnd2, edi, esi )

        .if ( [esi].token == T_OP_BRACKET || [esi].token == T_OP_SQ_BRACKET )

            xor ecx,ecx
            mov exp_token,T_CL_BRACKET
            .if ( [esi].token == T_OP_SQ_BRACKET )
                mov exp_token,T_CL_SQ_BRACKET
                mov ecx,EXPF_IN_SQBR
            .elseif ( [edi].flags & E_IS_DOT )
                mov opnd2.type,[edi].type
                or  opnd2.flags,E_IS_DOT
            .endif

            or  cl,flags
            and ecx,not EXPF_ONEOPND
            mov rc,evaluate( &opnd2, i, tokenarray, _end, cl )

            mov eax,i
            mov ebx,[eax]
            shl ebx,4
            add ebx,tokenarray
            mov eax,exp_token

            .if ( !( [ebx].token == al ) )

                .if ( rc != ERROR )
                    fnasmerr( 2157 )
                    mov eax,[edi].sym
                    .if ( ( [ebx].token == T_COMMA ) && eax && [eax].asym.state == SYM_UNDEFINED )
                        fnasmerr( 2006, [eax].asym.name )
                    .endif
                .endif
                mov rc,ERROR
            .else
                mov edx,i
                inc dword ptr [edx]
                add ebx,16
            .endif

        .elseif ( ( [ebx].token == T_OP_BRACKET || [ebx].token == T_OP_SQ_BRACKET || \
                    [ebx].token == '+' || [ebx].token == '-' || [ebx].token == T_UNARY_OPERATOR ) )
            movzx ecx,flags
            or ecx,EXPF_ONEOPND
            mov rc,evaluate( &opnd2, i, tokenarray, _end, cl )
        .else
            mov rc,get_operand( &opnd2, i, tokenarray, flags )
        .endif

        mov ecx,i
        mov ebx,[ecx]
        shl ebx,4
        add ebx,tokenarray

        movzx eax,[ebx].token
        .while ( rc != ERROR && ebx < last && eax != T_CL_BRACKET && eax != T_CL_SQ_BRACKET )

            .if ( eax == '+' || eax == '-' )
                mov [ebx].specval,1
            .elseif( !( eax >= T_OP_BRACKET || eax == T_UNARY_OPERATOR || \
                        eax == T_BINARY_OPERATOR ) || eax == T_UNARY_OPERATOR )

                ;; v2.26 - added for {k1}{z}..

                .if ( eax == T_STRING && [ebx].string_delim == '{' )

                    or [ebx].hll_flags,T_EVEX_OPT
                    mov edx,i
                    inc dword ptr [edx]
                    add ebx,16
                .else
                    mov rc,ERROR
                    .if !( [edi].flags & E_IS_OPEATTR )
                        mov ecx,i
                        OperErr( [ecx], tokenarray )
                    .endif
                .endif
                .break
            .endif
            get_precedence(ebx)
            push eax
            get_precedence(esi)
            pop ecx
            .break .if ecx >= eax
            mov cl,flags
            or  cl,EXPF_ONEOPND
            mov rc,evaluate( &opnd2, i, tokenarray, _end, cl )
            mov eax,i
            mov ebx,[eax]
            shl ebx,4
            add ebx,tokenarray
            movzx eax,[ebx].token
        .endw

        .if rc == ERROR && opnd2.flags & E_IS_OPEATTR
            .while( ebx < last && [ebx].token != T_CL_BRACKET && \
                 [ebx].token != T_CL_SQ_BRACKET )
                mov ecx,i
                inc dword ptr [ecx]
                add ebx,16
            .endw
            mov opnd2.kind,EXPR_EMPTY
            mov rc,NOT_ERROR
        .endif
        .if rc != ERROR
            mov rc,calculate( edi, &opnd2, esi )
        .endif
        .break .if ( flags & EXPF_ONEOPND )
    .endw
    mov eax,rc
    ret

evaluate endp

    option proc:public

EvalOperand proc uses esi ebx start_tok:ptr int_t, tokenarray:tok_t, end_tok:int_t,
        result:expr_t, flags:byte

    mov eax,start_tok
    mov ebx,[eax]
    mov esi,ebx
    shl ebx,4
    add ebx,tokenarray

    init_expr( result )
    .for( : esi < end_tok : esi++, ebx += 16 )

        ;; Check if a token is a valid part of an expression.
        ;; chars + - * / . : [] and () are operators.
        ;; also done here:
        ;; T_INSTRUCTION  SHL, SHR, AND, OR, XOR changed to T_BINARY_OPERATOR
        ;; T_INSTRUCTION  NOT                    changed to T_UNARY_OPERATOR
        ;; T_DIRECTIVE    PROC                   changed to T_STYPE
        ;; for the new operators the precedence is set.
        ;; DUP, comma or other instructions or directives terminate the expression.

        movzx eax,[ebx].token
        .switch eax
        .case T_INSTRUCTION
            mov eax,[ebx].tokval
            .switch eax
            .case T_SHL
            .case T_SHR
                mov [ebx].token,T_BINARY_OPERATOR
                mov [ebx].precedence,8
                .continue
            .case T_NOT
                mov [ebx].token,T_UNARY_OPERATOR
                mov [ebx].precedence,11
                .continue
            .case T_AND
                mov [ebx].token,T_BINARY_OPERATOR
                mov [ebx].precedence,12
                .continue
            .case T_OR
            .case T_XOR
                mov [ebx].token,T_BINARY_OPERATOR
                mov [ebx].precedence,13
                .continue
            .endsw
            .break
        .case T_RES_ID
            .break .if [ebx].tokval == T_DUP ;; DUP must terminate the expression
            .continue
        .case T_DIRECTIVE
            ;; PROC is converted to a type
            .if [ebx].tokval == T_PROC
                mov [ebx].token,T_STYPE
                ;; v2.06: avoid to use ST_PROC
                ;;item->bytval = ST_PROC;
                mov  dl,ModuleInfo._model
                mov  eax,1
                xchg ecx,edx
                shl  eax,cl
                mov  ecx,edx
                and  eax,SIZE_CODEPTR
                mov  eax,T_NEAR
                .ifnz
                    mov eax,T_FAR
                .endif
                mov [ebx].tokval,eax
                .continue
            .endif
            ;; fall through. Other directives will end the expression
        .case T_COMMA
            .break
        .endsw
    .endf

    mov edx,start_tok
    .return NOT_ERROR .if ( esi == [edx] )

    lea eax,asmerr
    .if flags & EXPF_NOERRMSG
        lea eax,noasmerr
    .endif
    mov fnasmerr,eax
    evaluate( result, edx, tokenarray, esi, flags )
    ret

EvalOperand endp

EmitConstError proc opnd:expr_t

    asmerr(2084)
    ret

EmitConstError endp

ExprEvalInit proc

    xor eax,eax
    mov thissym,eax
    mov nullstruct,eax
    mov nullmbr,eax
    ret

ExprEvalInit endp

    end
