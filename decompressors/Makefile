CXXFLAGS = `pkg-config --cflags QtCore` -D _CONSOLE -I.
LDFLAGS = -lstdc++ `pkg-config --libs QtCore`

all: jmm

jmm: jmm.o LZMA/LzmaDecompress.o LZMA/SDK/C/LzmaDec.o Tiano/EfiTianoDecompress.o


