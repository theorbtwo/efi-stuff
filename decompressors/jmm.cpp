/* ffsengine.ccp deals with compressed sections, around line 1327. 
 * algorithm passed in as COMPRESSION_ALGORITHM_UNKNOWN
 * result is true if errored.
 * body is a QByteArray of the body of the section (IE, not including the header).
 * decompressed doesn't appear to be initialized at all.  (Impying that it is from the default constructor of QByteArray?)
 */
/* QByteArray is part of QT? */
/* g++ -c -m64 -pipe -O2 -Wall -W -D_REENTRANT -DQT_WEBKIT -DQT_NO_DEBUG -DQT_GUI_LIB -DQT_CORE_LIB -DQT_SHARED -I/usr/share/qt4/mkspecs/linux-g++-64 -I. -I/usr/include/qt4/QtCore -I/usr/include/qt4/QtGui -I/usr/include/qt4 -I. -I. -o jmm.o jmm.cpp
g++ -m64 -Wl,-O1 -o jmm -L/usr/lib/x86_64-linux-gnu -lQtGui -lQtCore -lpthread
*/

#include <stdio.h>
#include <unistd.h>
#include <QByteArray>
#include "uefitool.h"
#include <Tiano/EfiTianoDecompress.h>
#include <LZMA/LzmaDecompress.h>

/* directly from ffs.cpp */
UINT32 sizeOfSectionHeader(const EFI_COMMON_SECTION_HEADER* header)
{
    if (!header)
        return 0;

    bool extended = false;
    /*if (uint24ToUint32(header->Size) == EFI_SECTION2_IS_USED) {
        extended = true;
    }*/

    switch (header->Type)
    {
    case EFI_SECTION_GUID_DEFINED: {
        if (!extended) {
            const EFI_GUID_DEFINED_SECTION* gdsHeader = (const EFI_GUID_DEFINED_SECTION*)header;
            if (QByteArray((const char*)&gdsHeader->SectionDefinitionGuid, sizeof(EFI_GUID)) == EFI_FIRMWARE_CONTENTS_SIGNED_GUID) {
                const WIN_CERTIFICATE* certificateHeader = (const WIN_CERTIFICATE*)(gdsHeader + 1);
                return gdsHeader->DataOffset + certificateHeader->Length;
            }
            return gdsHeader->DataOffset;
        }
        else {
            const EFI_GUID_DEFINED_SECTION2* gdsHeader = (const EFI_GUID_DEFINED_SECTION2*)header;
            if (QByteArray((const char*)&gdsHeader->SectionDefinitionGuid, sizeof(EFI_GUID)) == EFI_FIRMWARE_CONTENTS_SIGNED_GUID) {
                const WIN_CERTIFICATE* certificateHeader = (const WIN_CERTIFICATE*)(gdsHeader + 1);
                return gdsHeader->DataOffset + certificateHeader->Length;
            }
            return gdsHeader->DataOffset;
        }
    }
    case EFI_SECTION_COMPRESSION:           return extended ? sizeof(EFI_COMPRESSION_SECTION2) : sizeof(EFI_COMPRESSION_SECTION);
    case EFI_SECTION_DISPOSABLE:            return extended ? sizeof(EFI_DISPOSABLE_SECTION2) : sizeof(EFI_DISPOSABLE_SECTION);
    case EFI_SECTION_PE32:                  return extended ? sizeof(EFI_PE32_SECTION2) : sizeof(EFI_PE32_SECTION);
    case EFI_SECTION_PIC:                   return extended ? sizeof(EFI_PIC_SECTION2) : sizeof(EFI_PIC_SECTION);
    case EFI_SECTION_TE:                    return extended ? sizeof(EFI_TE_SECTION2) : sizeof(EFI_TE_SECTION);
    case EFI_SECTION_DXE_DEPEX:             return extended ? sizeof(EFI_DXE_DEPEX_SECTION2) : sizeof(EFI_DXE_DEPEX_SECTION);
    case EFI_SECTION_VERSION:               return extended ? sizeof(EFI_VERSION_SECTION2) : sizeof(EFI_VERSION_SECTION);
    case EFI_SECTION_USER_INTERFACE:        return extended ? sizeof(EFI_USER_INTERFACE_SECTION2) : sizeof(EFI_USER_INTERFACE_SECTION);
    case EFI_SECTION_COMPATIBILITY16:       return extended ? sizeof(EFI_COMPATIBILITY16_SECTION2) : sizeof(EFI_COMPATIBILITY16_SECTION);
    case EFI_SECTION_FIRMWARE_VOLUME_IMAGE: return extended ? sizeof(EFI_FIRMWARE_VOLUME_IMAGE_SECTION2) : sizeof(EFI_FIRMWARE_VOLUME_IMAGE_SECTION);
    case EFI_SECTION_FREEFORM_SUBTYPE_GUID: return extended ? sizeof(EFI_FREEFORM_SUBTYPE_GUID_SECTION2) : sizeof(EFI_FREEFORM_SUBTYPE_GUID_SECTION);
    case EFI_SECTION_RAW:                   return extended ? sizeof(EFI_RAW_SECTION2) : sizeof(EFI_RAW_SECTION);
    case EFI_SECTION_PEI_DEPEX:             return extended ? sizeof(EFI_PEI_DEPEX_SECTION2) : sizeof(EFI_PEI_DEPEX_SECTION);
    case EFI_SECTION_SMM_DEPEX:             return extended ? sizeof(EFI_SMM_DEPEX_SECTION2) : sizeof(EFI_SMM_DEPEX_SECTION);
    case INSYDE_SECTION_POSTCODE:           return extended ? sizeof(POSTCODE_SECTION2) : sizeof(POSTCODE_SECTION);
    case SCT_SECTION_POSTCODE:              return extended ? sizeof(POSTCODE_SECTION2) : sizeof(POSTCODE_SECTION);
    default:                                return extended ? sizeof(EFI_COMMON_SECTION_HEADER2) : sizeof(EFI_COMMON_SECTION_HEADER);
    }
}

/* Taken almost directly from ffsengine.cpp */
UINT8 decompress(const QByteArray & compressedData, const UINT8 compressionType, QByteArray & decompressedData, UINT8 * algorithm)
{
    const UINT8* data;
    UINT32 dataSize;
    UINT8* decompressed;
    UINT32 decompressedSize = 0;
    UINT8* scratch;
    UINT32 scratchSize = 0;
    const EFI_TIANO_HEADER* header;

    switch (compressionType)
    {
    case EFI_NOT_COMPRESSED:
        decompressedData = compressedData;
        if (algorithm)
            *algorithm = COMPRESSION_ALGORITHM_NONE;
        return ERR_SUCCESS;
    case EFI_STANDARD_COMPRESSION:
        // Get buffer sizes
        data = (UINT8*)compressedData.data();
        dataSize = compressedData.size();

        // Check header to be valid
        header = (const EFI_TIANO_HEADER*)data;
        fprintf(stderr, "CompSize (tianto header): %d = 0x%x\n", header->CompSize, header->CompSize);
        fprintf(stderr, "OrigSize (tianto header): %d = 0x%x\n", header->OrigSize, header->OrigSize);
        if (header->CompSize + sizeof(EFI_TIANO_HEADER) != dataSize) {
            fprintf(stderr, "sizes don't work out: header-comp-size=0x%x, sizeof(EFI_TIANTO_HEADER)=0x%lx dataSize=0x%x\n",
                    header->CompSize, sizeof(EFI_TIANO_HEADER), dataSize);
            return ERR_STANDARD_DECOMPRESSION_FAILED;
        }

        // Get info function is the same for both algorithms
        if (ERR_SUCCESS != EfiTianoGetInfo(data, dataSize, &decompressedSize, &scratchSize))
            return ERR_STANDARD_DECOMPRESSION_FAILED;

        // Allocate memory
        decompressed = new UINT8[decompressedSize];
        scratch = new UINT8[scratchSize];

        // Decompress section data

        //TODO: separate EFI1.1 from Tiano another way
        // Try Tiano decompression first
        if (ERR_SUCCESS != TianoDecompress(data, dataSize, decompressed, decompressedSize, scratch, scratchSize)) {
            // Not Tiano, try EFI 1.1
            if (ERR_SUCCESS != EfiDecompress(data, dataSize, decompressed, decompressedSize, scratch, scratchSize)) {
                if (algorithm)
                    *algorithm = COMPRESSION_ALGORITHM_UNKNOWN;

                delete[] decompressed;
                delete[] scratch;
                return ERR_STANDARD_DECOMPRESSION_FAILED;
            }
            else if (algorithm)
                *algorithm = COMPRESSION_ALGORITHM_EFI11;
        }
        else if (algorithm)
            *algorithm = COMPRESSION_ALGORITHM_TIANO;

        decompressedData = QByteArray((const char*)decompressed, decompressedSize);

        delete[] decompressed;
        delete[] scratch;
        return ERR_SUCCESS;
    case EFI_CUSTOMIZED_COMPRESSION:
        // Get buffer sizes
        data = (const UINT8*)compressedData.constData();
        dataSize = compressedData.size();

        // Get info
        if (ERR_SUCCESS != LzmaGetInfo(data, dataSize, &decompressedSize))
            return ERR_CUSTOMIZED_DECOMPRESSION_FAILED;

        // Allocate memory
        decompressed = new UINT8[decompressedSize];

        // Decompress section data
        if (ERR_SUCCESS != LzmaDecompress(data, dataSize, decompressed)) {
            // Intel modified LZMA workaround
            EFI_COMMON_SECTION_HEADER* shittySectionHeader;
            UINT32 shittySectionSize;
            // Shitty compressed section with a section header between COMPRESSED_SECTION_HEADER and LZMA_HEADER
            // We must determine section header size by checking it's type before we can unpack that non-standard compressed section
            shittySectionHeader = (EFI_COMMON_SECTION_HEADER*)data;
            shittySectionSize = sizeOfSectionHeader(shittySectionHeader);

            // Decompress section data once again
            data += shittySectionSize;

            // Get info again
            if (ERR_SUCCESS != LzmaGetInfo(data, dataSize, &decompressedSize)) {
                delete[] decompressed;
                return ERR_CUSTOMIZED_DECOMPRESSION_FAILED;
            }

            // Decompress section data again
            if (ERR_SUCCESS != LzmaDecompress(data, dataSize, decompressed)) {
                if (algorithm)
                    *algorithm = COMPRESSION_ALGORITHM_UNKNOWN;
                delete[] decompressed;
                return ERR_CUSTOMIZED_DECOMPRESSION_FAILED;
            }
            else {
                if (algorithm)
                    *algorithm = COMPRESSION_ALGORITHM_IMLZMA;
                decompressedData = QByteArray((const char*)decompressed, decompressedSize);
            }
        }
        else {
            if (algorithm)
                *algorithm = COMPRESSION_ALGORITHM_LZMA;
            decompressedData = QByteArray((const char*)decompressed, decompressedSize);
        }

        delete[] decompressed;
        return ERR_SUCCESS;
    default:
        printf("decompress: unknown compression type %d\n", compressionType);
        if (algorithm)
            *algorithm = COMPRESSION_ALGORITHM_UNKNOWN;
        return ERR_UNKNOWN_COMPRESSION_ALGORITHM;
    }
}

int main(int argc, char *argv[]) {
  UINT8 result;
  UINT8 algorithm = COMPRESSION_ALGORITHM_UNKNOWN;
  UINT8 compression_type = 1;
  QByteArray body;
  QByteArray decompressed;
  int buffer_size = 1024;
  char buffer[buffer_size];
  ssize_t readlen;

  if (argc != 2) {
    fprintf(stderr, "ERROR: pass %s a single argument, the (integer) compression type\n", argv[0]);
    return 1;
  }
  
  compression_type = atoi(argv[1]);
  fprintf(stderr, "Compression type: %d\n", compression_type);
          
  while ((readlen = read(0, buffer, buffer_size))) {
    // 0 -> reached eof.
    body.append(buffer, readlen);
  }
  
  result = decompress(body, compression_type, decompressed, &algorithm);
  if (result) {
    fprintf(stderr, "Error decompressing: %d\n", result);
    return 2;
  }

  fprintf(stderr, "Decompressed size: %d\n", decompressed.size());
  readlen = write(1, decompressed.data(), decompressed.size());
  if (readlen != decompressed.size()) {
    perror("Error writing output: ");
    return 3;
  }
}


