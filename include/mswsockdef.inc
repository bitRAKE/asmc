ifndef _MSWSOCKDEF_
_MSWSOCKDEF_ equ <>

include winapifamily.inc

if(_WIN32_WINNT GE 0x0600)

ifdef _WS2DEF_

externdef sockaddr_size:BYTE

SOCKADDR_SIZE macro af
    if (af LT AF_MAX)
	exitm<sockaddr_size[af]>
    else
	exitm<sockaddr_size[AF_UNSPEC]>
    endif
    endm

ScopeLevel macro ScopeId
    exitm<ScopeId.SCOPE_LEVEL.Level>
    endm

endif

SIO_SET_COMPATIBILITY_MODE equ _WSAIOW(IOC_VENDOR,300)

WSA_COMPATIBILITY_BEHAVIOR_ID typedef SDWORD
WsaBehaviorAll		equ 0
WsaBehaviorReceiveBuffering equ 1
WsaBehaviorAutoTuning	equ 2

WSA_COMPATIBILITY_MODE	STRUC
BehaviorId		WSA_COMPATIBILITY_BEHAVIOR_ID ?
TargetOsVersion		ULONG ?
WSA_COMPATIBILITY_MODE	ENDS
PWSA_COMPATIBILITY_MODE typedef ptr WSA_COMPATIBILITY_MODE

endif ;;(_WIN32_WINNT GE 0x0600)

RIO_BUFFERID		typedef DWORD;RIO_BUFFERID_t
PRIO_BUFFERID		typedef ptr RIO_BUFFERID
RIO_CQ			typedef DWORD;RIO_RQ_t
PRIO_CQ			typedef ptr RIO_CQ
RIO_RQ			typedef DWORD;RIO_RQ_t
PRIO_RQ			typedef ptr RIO_RQ

RIORESULT		STRUC
Status			LONG ?
BytesTransferred	ULONG ?
SocketContext		ULONGLONG ?
RequestContext		ULONGLONG ?
RIORESULT		ENDS
PRIORESULT		typedef ptr RIORESULT

RIO_BUF			STRUC
BufferId		RIO_BUFFERID ?
_Offset			ULONG ?
_Length			ULONG ?
RIO_BUF			ENDS
PRIO_BUF		typedef ptr RIO_BUF

RIO_MSG_DONT_NOTIFY	equ 0x00000001
RIO_MSG_DEFER		equ 0x00000002
RIO_MSG_WAITALL		equ 0x00000004
RIO_MSG_COMMIT_ONLY	equ 0x00000008

RIO_INVALID_BUFFERID	equ (0xFFFFFFFF)
RIO_INVALID_CQ		equ (0)
RIO_INVALID_RQ		equ (0)

RIO_MAX_CQ_SIZE		equ 0x8000000
RIO_CORRUPT_CQ		equ 0xFFFFFFFF

RIO_CMSG_BUFFER		STRUC
TotalLength		ULONG ?
RIO_CMSG_BUFFER		ENDS
PRIO_CMSG_BUFFER	typedef ptr RIO_CMSG_BUFFER

RIO_CMSG_BASE_SIZE	equ WSA_CMSGHDR_ALIGN(sizeof(RIO_CMSG_BUFFER))

endif  ;; _MSWSOCKDEF_