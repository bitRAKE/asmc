include direct.inc
include errno.inc

	.code

_mkdir	proc directory:LPSTR

local	wpath

	.if	!CreateDirectoryA( directory, 0 )

		mov	wpath,__allocwpath( directory )
		add	eax,8
		.if	!CreateDirectoryW( eax, 0 )

			CreateDirectoryW( wpath, 0 )
		.endif
	.endif

	.if	!eax

		osmaperr()
	.else
		mov	_diskflag,1
		xor	eax,eax
	.endif
	ret

_mkdir	endp

	END
