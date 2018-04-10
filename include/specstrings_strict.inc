ifndef __SPECSTRINGS_STRICT_LEVEL
__SPECSTRINGS_STRICT_LEVEL equ 1
endif

if (_MSC_VER GE 1400) AND NOT defined(__midl) AND NOT defined(_PREFAST_) AND (__SPECSTRINGS_STRICT_LEVEL GT 0)

include specstrings_undef.inc

if (__SPECSTRINGS_STRICT_LEVEL GT 1)
endif

if NOT defined(_MSC_EXTENSIONS) AND NOT defined(_PREFAST_) AND NOT defined(OACR)

else

if (__SPECSTRINGS_STRICT_LEVEL EQ 1) OR (__SPECSTRINGS_STRICT_LEVEL EQ 2)
endif

endif

endif
