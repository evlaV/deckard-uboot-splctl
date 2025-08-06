//========= Copyright Valve Corporation ============//
#ifndef BOOT_INFO_H
#define BOOT_INFO_H

#include <stdint.h>

#if defined(DBOOTCTL_SBL)
uint32_t crc32( uint32_t inCrc32, const void *buf, size_t bufLen );
#define nullptr NULL
#define stricmp strcasecmp
#define _stricmp strcasecmp
#define strnicmp strncasecmp
#define strcmpi strcasecmp
#endif

#pragma pack(push)
#pragma pack(1)

typedef enum _ESlot
{
	Slot_Unknown = -1,
	Slot_A = 0,
	Slot_B = 1,
	Slot_Recovery = 2,

	Slot_Max
} ESlot;

#define SLOT_FLAG_GOOD 1<<0

typedef struct _SlotInfo_t
{
	uint32_t unFlags;
	uint8_t unFailedStartCount;
	uint8_t reserved1[3];
	uint32_t reserved2[ 2 ];
} SlotInfo_t;

typedef struct _BootInfo_t
{
	uint32_t unMagic;
	uint16_t unMajorVersion;
	uint16_t unMinorVersion;

	uint8_t unActiveSlot;

	uint8_t reserved1[ 3 ];
	uint32_t reserved2;

	SlotInfo_t rSlot[ Slot_Max ];

	uint32_t reserved3[ 15 ];

	uint32_t unCrc;
} BootInfo_t;

#pragma pack(pop)

#define BOOT_INFO_EXPECTED_SIZE 32*4

#define BOOT_INFO_MAGIC 0x46DFEB70

#define BOOT_INFO_MAJOR_VERSION 1
#define BOOT_INFO_MINOR_VERSION 2

const char *GetSlotName( ESlot eSlot );
typedef  void ( *FnErrorHandler )( const char * );
int VerifyBootInfo( BootInfo_t* pBootInfo, int nBytesRead, FnErrorHandler fnErrorHandler );

inline int VerifyBootInfo( BootInfo_t* pBootInfo, int nBytesRead, FnErrorHandler fnErrorHandler )
{
	#define ERRBUFFLEN 128
	char errorBuf[ ERRBUFFLEN ];
 	if ( nBytesRead != sizeof( BootInfo_t ) )
	{
		snprintf( errorBuf, ERRBUFFLEN, "Read %d bytes but expected %d bytes.\n", nBytesRead, (int)sizeof( BootInfo_t ) );
		fnErrorHandler( errorBuf );
		return -3;
	}

	if ( pBootInfo->unMagic != BOOT_INFO_MAGIC )
	{
		snprintf( errorBuf, ERRBUFFLEN, "Boot info must have magic header value 0x%X, but had 0x%X instead\n",
			BOOT_INFO_MAGIC, pBootInfo->unMagic );
		fnErrorHandler( errorBuf );
		return -4;
	}

	uint32_t unComputedCrc = crc32( 0, pBootInfo, sizeof( BootInfo_t ) - sizeof( uint32_t ) );
	if ( unComputedCrc != pBootInfo->unCrc )
	{
		snprintf( errorBuf, ERRBUFFLEN, "Boot info had CRC 0x%X, but computed CRC was 0x%X\n",
			pBootInfo->unCrc, unComputedCrc );
		fnErrorHandler( errorBuf );
		return -5;
	}

	if ( pBootInfo->unMajorVersion != BOOT_INFO_MAJOR_VERSION )
	{
		snprintf( errorBuf, ERRBUFFLEN, "This binary uses boot info version %d.%d, but the boot info file has %d.%d.",
			BOOT_INFO_MAJOR_VERSION, BOOT_INFO_MINOR_VERSION,
			pBootInfo->unMajorVersion, pBootInfo->unMinorVersion );
		fnErrorHandler( errorBuf );
		return -6;
	}

	return 0;
}

inline void UpdateBootInfoCrc( BootInfo_t* pBootInfo )
{
	pBootInfo->unCrc = crc32( 0, pBootInfo, sizeof( BootInfo_t ) - sizeof( uint32_t ) );
}

inline void InitBootInfo( BootInfo_t *pBootInfo )
{
	memset( pBootInfo, 0, sizeof( BootInfo_t ) );
	pBootInfo->unMagic = BOOT_INFO_MAGIC;
	pBootInfo->unMajorVersion = BOOT_INFO_MAJOR_VERSION;
	pBootInfo->unMinorVersion = BOOT_INFO_MINOR_VERSION;
	// CRC will be taken care of when writing
}

inline const char *GetSlotName( ESlot eSlot )
{
	switch ( eSlot )
	{
		case Slot_A:
			return "A";
		case Slot_B:
			return "B";
		case Slot_Recovery:
			return "Recovery";

		default:
			return nullptr;
	}
}

inline ESlot GetSlotEnumFromName( const char *pchSlotName )
{
	for ( int i = 0; i < Slot_Max; i++ )
	{
		const char *pchTestName = GetSlotName( ( ESlot )i );
		if ( !pchTestName )
			continue;

		if ( !stricmp( pchSlotName, pchTestName ) )
			return ( ESlot )i;
	}
	return Slot_Unknown;
}

#endif // BOOT_INFO_H
