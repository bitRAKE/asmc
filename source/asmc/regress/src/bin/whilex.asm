; v2.22 - Test for pre-existing flag conditions in .WHILEx

	.386
	.MODEL	FLAT
	.CODE

	.WHILEA
	.ENDW
	.WHILEAE
	.ENDW
	.WHILEB
	.ENDW
	.WHILEBE
	.ENDW
	.WHILEC
	.ENDW
	.WHILEE
	.ENDW
	.WHILEG
	.ENDW
	.WHILEGE
	.ENDW
	.WHILEL
	.ENDW
	.WHILELE
	.ENDW
	.WHILENA
	.ENDW
	.WHILENAE
	.ENDW
	.WHILENB
	.ENDW
	.WHILENBE
	.ENDW
	.WHILENC
	.ENDW
	.WHILENE
	.ENDW
	.WHILENG
	.ENDW
	.WHILENGE
	.ENDW
	.WHILENL
	.ENDW
	.WHILENLE
	.ENDW
	.WHILENO
	.ENDW
	.WHILENP
	.ENDW
	.WHILENS
	.ENDW
	.WHILENZ
	.ENDW
	.WHILEO
	.ENDW
	.WHILEP
	.ENDW
	.WHILEPE
	.ENDW
	.WHILEPO
	.ENDW
	.WHILES
	.ENDW
	.WHILEZ
		.BREAK .IFA
		.CONTINUE .IFS
	.ENDW

	END
