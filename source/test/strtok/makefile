msvc = 0

strtok.exe:
!if $(msvc)
    asmc64 -pe $*.asm
!else
    asmc64 $*.asm
    linkw op map sys con_64 file $*
    del *.obj
!endif
    $@ *.asm
    pause

