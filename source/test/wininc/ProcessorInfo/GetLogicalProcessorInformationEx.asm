include windows.inc
include stdio.inc
include malloc.inc
include tchar.inc

LPFN_GLPIX_T typedef proto WINAPI :LOGICAL_PROCESSOR_RELATIONSHIP, :PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX, :LPDWORD
LPFN_GLPIX   typedef ptr LPFN_GLPIX_T

	.code

; pretty within reason
GroupMask_Helper PROC gAff:GROUP_AFFINITY
	mov rcx,gAff
	assume rcx:PTR GROUP_AFFINITY
	bsf r8,[rcx].Mask
	bsr r9,[rcx].Mask
	_tprintf("\tGroup %d consisting of cores: %d-%d\n",[rcx]._Group,r8,r9)
	ret
GroupMask_Helper ENDP


_tmain proc
	local glpix:LPFN_GLPIX
	local buffer:PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX
	local retLength[2]:DWORD

	.if !GetProcAddress(
		GetModuleHandle("kernel32"), "GetLogicalProcessorInformationEx")
		_tprintf("\nGetLogicalProcessorInformationEx is not supported.\n")
		exit(1)
	.endif
	mov glpix,rax

	and [buffer],0
	and QWORD PTR[retLength],0
	jmp entry

  alloc_fail:
	_tprintf("\nError: Allocation failure\n")
	exit(2)
  fail:
	GetLastError()
	cmp eax,ERROR_INSUFFICIENT_BUFFER
	jz @F
	_tprintf("\nError %d\n", eax)
	exit(3)
  @@:
	malloc(retLength)
	xchg rcx,rax
	jrcxz alloc_fail
	mov [buffer],rcx
  entry:
	glpix(RelationAll,buffer,&retLength)
	xchg ecx,eax ; BOOL
	jrcxz fail

	mov rdi,[buffer]
	add QWORD PTR[retLength],rdi
	assume rdi:ptr SYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX
  relate:
	.switch ([rdi].Relationship)

; Note: decreasing relationship hierarchy ...

	.case RelationNumaNode
		_tprintf("\nNuma Node %d:\n",[rdi].NumaNode.NodeNumber)
		GroupMask_Helper([rdi].NumaNode.GroupMask)
		.endc
		
	.case RelationProcessorPackage
		_tprintf("\nPackage: ")
		.if [rdi].Processor.GroupCount != 1
			_tprintf("Each NUMA node is assigned %d groups.\n",[rdi].Processor.GroupCount)
		.else
			_tprintf("All processors are in the same group.\n")
		.endif

;		lea rsi,[rdi].Processor.GroupMask
;		movzx ebx,[rdi].Processor.GroupCount
;		.repeat
;			dec ebx
;			GroupMask_Helper([rsi])
;			lea rsi,[rsi+sizeof(GROUP_AFFINITY)]
;		.until ebx == 0

		.if [rdi].Processor.Flags
			_tprintf("\tConsists of multiple cores (unexpected)!\n")
		.endif
		.endc
		
	.case RelationGroup
		_tprintf("\nGroup(s):\n")
		_tprintf("\t%d group(s) of %d, are active.\n",
			[rdi]._Group.ActiveGroupCount,[rdi]._Group.MaximumGroupCount)
		movzx ebx,[rdi]._Group.ActiveGroupCount
		.while ebx
			dec ebx
			lea rsi,[rdi]._Group.GroupInfo
			assume rsi:ptr PROCESSOR_GROUP_INFO
			_tprintf("\tGroup %d: %d processor(s) of %d, are active.\n",
				ebx,[rsi].ActiveProcessorCount,[rsi].MaximumProcessorCount)

			; if some cores are disabled should probably show mask?

			add rsi,sizeof(PROCESSOR_GROUP_INFO)
		.endw
		.endc
		
	.case RelationProcessorCore
		.if [rdi].Processor.Flags
			_tprintf("\nSMT Core: ")
		.else
			_tprintf("\nCore: ")
		.endif

		; EfficiencyClass

		GroupMask_Helper([rdi].Processor.GroupMask)
		.endc
		
	.case RelationCache
		mov edx,4
		mov eax,[rdi].Cache.Type
		cmp eax,edx
		cmovnc eax,edx
		mov rdx,cacheTypeTab
		mov rax,[rdx+rax*8]
		_tprintf("\nL%d %s Cache: ",[rdi].Cache.Level,rax)
		_tprintf("%d bytes, %d-way associative, %d byte lines.\n",
			[rdi].Cache.CacheSize,
			[rdi].Cache.Associativity,
			[rdi].Cache.LineSize)
		GroupMask_Helper([rdi].Cache.GroupMask)
		.endc

	.default
		_tprintf("Error: Unsupported LOGICAL_PROCESSOR_RELATIONSHIP value.\n")
		.endc
	.endsw

	mov eax,[rdi].Size
	lea rdi,[rdi+rax]
	cmp rdi,QWORD PTR[retLength]
	jc relate
	jz @F

	_tprintf("\nError: Unexpected buffer size.\n")

  @@:	free(buffer)
	exit(0)
_tmain endp


align 8
cacheTypeTab: dq @CStr("Unified"),
@CStr("Instruction"),
@CStr("Data"),
@CStr("Trace"),
@CStr("Unknown")

end _tmain