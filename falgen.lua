-- falgen.lua
-- Roblox Studio plugin: 3D generation in Studio via fal.ai (Tripo P1)
--
-- Drop into %LOCALAPPDATA%\Roblox\Plugins\ and restart Studio.
-- BYO fal key - paste it into the widget the first time you open it.

if not plugin then
	warn("[falgen] not running as a plugin")
	return
end

local HttpService = game:GetService("HttpService")
local StudioService = game:GetService("StudioService")
local AssetService = game:GetService("AssetService")

-- ===== vendored: sircfenner/png-luau v0.2.1 - single-file PNG decoder =====
-- MIT License · Copyright (c) sircfenner · https://github.com/sircfenner/png-luau
-- Inlined below as a self-contained module (decodes fal PNGs for in-Studio preview).
local PNG = (function()
--!strict
--!native
--!optimize 2
type PNG__DARKLUA_TYPE_a = {
	width: number,
	height: number,
	pixels: buffer,
	readPixel: (x: number, y: number) -> (number, number, number, number),
}

type Chunk__DARKLUA_TYPE_b = {
	type: string,
	offset: number,
	length: number,
}

type IHDRChunk__DARKLUA_TYPE_c = {
	width: number,
	height: number,
	bitDepth: number,
	colorType: number,
	interlaced: boolean,
}

type PaletteColor__DARKLUA_TYPE_d = {
	r: number,
	g: number,
	b: number,
	a: number,
}

type PLTEChunk__DARKLUA_TYPE_e = {
	colors: { PaletteColor__DARKLUA_TYPE_d },
}

type tRNSChunk__DARKLUA_TYPE_f = {
	gray: number,
	red: number,
	green: number,
	blue: number,
}

type HuffmanTable__DARKLUA_TYPE_g = { number }
local __BUNDLE = { cache = {} :: any }
do
	do
		local function __modImpl()
			return {}
		end
		function __BUNDLE.a(): typeof(__modImpl())
			local v = __BUNDLE.cache.a
			if not v then
				v = { c = __modImpl() }
				__BUNDLE.cache.a = v
			end
			return v.c
		end
	end
	do
		local function __modImpl()
			__BUNDLE.a()

			local COLOR_TYPE_BIT_DEPTH = {
				[0] = { 1, 2, 4, 8, 16 },
				[2] = { 8, 16 },
				[3] = { 1, 2, 4, 8 },
				[4] = { 8, 16 },
				[6] = { 8, 16 },
			}

			local function read(buf: buffer, chunk: Chunk__DARKLUA_TYPE_b): IHDRChunk__DARKLUA_TYPE_c
				assert(chunk.length == 13, "IHDR data must be 13 bytes")

				local offset = chunk.offset

				local width = bit32.byteswap(buffer.readu32(buf, offset))
				local height = bit32.byteswap(buffer.readu32(buf, offset + 4))
				local bitDepth = buffer.readu8(buf, offset + 8)
				local colorType = buffer.readu8(buf, offset + 9)
				local compression = buffer.readu8(buf, offset + 10)
				local filter = buffer.readu8(buf, offset + 11)
				local interlace = buffer.readu8(buf, offset + 12)

				assert(width > 0 and width <= 2 ^ 31 and height > 0 and height <= 2 ^ 31, "invalid dimensions")
				assert(compression == 0, "invalid compression method")
				assert(filter == 0, "invalid filter method")
				assert(interlace == 0 or interlace == 1, "invalid interlace method")

				local allowedBitDepth = COLOR_TYPE_BIT_DEPTH[colorType]
				assert(allowedBitDepth ~= nil, "invalid color type")
				assert(table.find(allowedBitDepth, bitDepth) ~= nil, "invalid bit depth")

				return {
					width = width,
					height = height,
					bitDepth = bitDepth,
					colorType = colorType,
					interlaced = interlace == 1,
				}
			end

			return read
		end
		function __BUNDLE.b(): typeof(__modImpl())
			local v = __BUNDLE.cache.b
			if not v then
				v = { c = __modImpl() }
				__BUNDLE.cache.b = v
			end
			return v.c
		end
	end
	do
		local function __modImpl()
			__BUNDLE.a()

			local function read(
				buf: buffer,
				chunk: Chunk__DARKLUA_TYPE_b,
				header: IHDRChunk__DARKLUA_TYPE_c
			): PLTEChunk__DARKLUA_TYPE_e
				assert(chunk.length % 3 == 0, "malformed PLTE chunk")

				local count = chunk.length / 3
				assert(count > 0, "no entries in PLTE")
				assert(count <= 256, "too many entries in PLTE")
				assert(count <= 2 ^ header.bitDepth, "too many entries in PLTE for bit depth")

				local colors = table.create(count)
				local offset = chunk.offset

				for i = 1, count do
					colors[i] = {
						r = buffer.readu8(buf, offset),
						g = buffer.readu8(buf, offset + 1),
						b = buffer.readu8(buf, offset + 2),
						a = 255,
					}
					offset += 3
				end

				return {
					colors = colors,
				}
			end

			return read
		end
		function __BUNDLE.c(): typeof(__modImpl())
			local v = __BUNDLE.cache.c
			if not v then
				v = { c = __modImpl() }
				__BUNDLE.cache.c = v
			end
			return v.c
		end
	end
	do
		local function __modImpl()
			__BUNDLE.a()

			local function readU16(buf: buffer, offset: number, depth: number)
				return bit32.extract(
					bit32.bor(bit32.lshift(buffer.readu8(buf, offset), 8), buffer.readu8(buf, offset + 1)),
					0,
					depth
				)
			end

			local function read(
				buf: buffer,
				chunk: Chunk__DARKLUA_TYPE_b,
				header: IHDRChunk__DARKLUA_TYPE_c,
				palette: PLTEChunk__DARKLUA_TYPE_e?
			): tRNSChunk__DARKLUA_TYPE_f
				local gray = -1
				local red = -1
				local green = -1
				local blue = -1

				if header.colorType == 0 then
					assert(chunk.length == 2, "invalid tRNS length for color type")
					gray = readU16(buf, chunk.offset, header.bitDepth)
				elseif header.colorType == 2 then
					assert(chunk.length == 6, "invalid tRNS length for color type")
					red = readU16(buf, chunk.offset, header.bitDepth)
					green = readU16(buf, chunk.offset + 2, header.bitDepth)
					blue = readU16(buf, chunk.offset + 4, header.bitDepth)
				else
					local count = chunk.length
					assert(palette, "tRNS requires PLTE for color type")
					assert(count <= #palette.colors, "tRNS specified too many PLTE alphas")
					for i = 1, count do
						palette.colors[i].a = buffer.readu8(buf, chunk.offset + i - 1)
					end
				end

				return {
					gray = gray,
					red = red,
					green = green,
					blue = blue,
				}
			end

			return read
		end
		function __BUNDLE.d(): typeof(__modImpl())
			local v = __BUNDLE.cache.d
			if not v then
				v = { c = __modImpl() }
				__BUNDLE.cache.d = v
			end
			return v.c
		end
	end
	do
		local function __modImpl()
			return {
				IHDR = __BUNDLE.b(),
				PLTE = __BUNDLE.c(),
				tRNS = __BUNDLE.d(),
			}
		end
		function __BUNDLE.e(): typeof(__modImpl())
			local v = __BUNDLE.cache.e
			if not v then
				v = { c = __modImpl() }
				__BUNDLE.cache.e = v
			end
			return v.c
		end
	end
	do
		local function __modImpl()


-- stylua: ignore

local lookup = {
	0x00000000, 0x77073096, 0xEE0E612C, 0x990951BA, 0x076DC419, 0x706AF48F, 0xE963A535, 0x9E6495A3,
	0x0EDB8832, 0x79DCB8A4, 0xE0D5E91E, 0x97D2D988, 0x09B64C2B, 0x7EB17CBD, 0xE7B82D07, 0x90BF1D91,
	0x1DB71064, 0x6AB020F2, 0xF3B97148, 0x84BE41DE, 0x1ADAD47D, 0x6DDDE4EB, 0xF4D4B551, 0x83D385C7,
	0x136C9856, 0x646BA8C0, 0xFD62F97A, 0x8A65C9EC, 0x14015C4F, 0x63066CD9, 0xFA0F3D63, 0x8D080DF5,
	0x3B6E20C8, 0x4C69105E, 0xD56041E4, 0xA2677172, 0x3C03E4D1, 0x4B04D447, 0xD20D85FD, 0xA50AB56B,
	0x35B5A8FA, 0x42B2986C, 0xDBBBC9D6, 0xACBCF940, 0x32D86CE3, 0x45DF5C75, 0xDCD60DCF, 0xABD13D59,
	0x26D930AC, 0x51DE003A, 0xC8D75180, 0xBFD06116, 0x21B4F4B5, 0x56B3C423, 0xCFBA9599, 0xB8BDA50F,
	0x2802B89E, 0x5F058808, 0xC60CD9B2, 0xB10BE924, 0x2F6F7C87, 0x58684C11, 0xC1611DAB, 0xB6662D3D,
	0x76DC4190, 0x01DB7106, 0x98D220BC, 0xEFD5102A, 0x71B18589, 0x06B6B51F, 0x9FBFE4A5, 0xE8B8D433,
	0x7807C9A2, 0x0F00F934, 0x9609A88E, 0xE10E9818, 0x7F6A0DBB, 0x086D3D2D, 0x91646C97, 0xE6635C01,
	0x6B6B51F4, 0x1C6C6162, 0x856530D8, 0xF262004E, 0x6C0695ED, 0x1B01A57B, 0x8208F4C1, 0xF50FC457,
	0x65B0D9C6, 0x12B7E950, 0x8BBEB8EA, 0xFCB9887C, 0x62DD1DDF, 0x15DA2D49, 0x8CD37CF3, 0xFBD44C65,
	0x4DB26158, 0x3AB551CE, 0xA3BC0074, 0xD4BB30E2, 0x4ADFA541, 0x3DD895D7, 0xA4D1C46D, 0xD3D6F4FB,
	0x4369E96A, 0x346ED9FC, 0xAD678846, 0xDA60B8D0, 0x44042D73, 0x33031DE5, 0xAA0A4C5F, 0xDD0D7CC9,
	0x5005713C, 0x270241AA, 0xBE0B1010, 0xC90C2086, 0x5768B525, 0x206F85B3, 0xB966D409, 0xCE61E49F,
	0x5EDEF90E, 0x29D9C998, 0xB0D09822, 0xC7D7A8B4, 0x59B33D17, 0x2EB40D81, 0xB7BD5C3B, 0xC0BA6CAD,
	0xEDB88320, 0x9ABFB3B6, 0x03B6E20C, 0x74B1D29A, 0xEAD54739, 0x9DD277AF, 0x04DB2615, 0x73DC1683,
	0xE3630B12, 0x94643B84, 0x0D6D6A3E, 0x7A6A5AA8, 0xE40ECF0B, 0x9309FF9D, 0x0A00AE27, 0x7D079EB1,
	0xF00F9344, 0x8708A3D2, 0x1E01F268, 0x6906C2FE, 0xF762575D, 0x806567CB, 0x196C3671, 0x6E6B06E7,
	0xFED41B76, 0x89D32BE0, 0x10DA7A5A, 0x67DD4ACC, 0xF9B9DF6F, 0x8EBEEFF9, 0x17B7BE43, 0x60B08ED5,
	0xD6D6A3E8, 0xA1D1937E, 0x38D8C2C4, 0x4FDFF252, 0xD1BB67F1, 0xA6BC5767, 0x3FB506DD, 0x48B2364B,
	0xD80D2BDA, 0xAF0A1B4C, 0x36034AF6, 0x41047A60, 0xDF60EFC3, 0xA867DF55, 0x316E8EEF, 0x4669BE79,
	0xCB61B38C, 0xBC66831A, 0x256FD2A0, 0x5268E236, 0xCC0C7795, 0xBB0B4703, 0x220216B9, 0x5505262F,
	0xC5BA3BBE, 0xB2BD0B28, 0x2BB45A92, 0x5CB36A04, 0xC2D7FFA7, 0xB5D0CF31, 0x2CD99E8B, 0x5BDEAE1D,
	0x9B64C2B0, 0xEC63F226, 0x756AA39C, 0x026D930A, 0x9C0906A9, 0xEB0E363F, 0x72076785, 0x05005713,
	0x95BF4A82, 0xE2B87A14, 0x7BB12BAE, 0x0CB61B38, 0x92D28E9B, 0xE5D5BE0D, 0x7CDCEFB7, 0x0BDBDF21,
	0x86D3D2D4, 0xF1D4E242, 0x68DDB3F8, 0x1FDA836E, 0x81BE16CD, 0xF6B9265B, 0x6FB077E1, 0x18B74777,
	0x88085AE6, 0xFF0F6A70, 0x66063BCA, 0x11010B5C, 0x8F659EFF, 0xF862AE69, 0x616BFFD3, 0x166CCF45,
	0xA00AE278, 0xD70DD2EE, 0x4E048354, 0x3903B3C2, 0xA7672661, 0xD06016F7, 0x4969474D, 0x3E6E77DB,
	0xAED16A4A, 0xD9D65ADC, 0x40DF0B66, 0x37D83BF0, 0xA9BCAE53, 0xDEBB9EC5, 0x47B2CF7F, 0x30B5FFE9,
	0xBDBDF21C, 0xCABAC28A, 0x53B39330, 0x24B4A3A6, 0xBAD03605, 0xCDD70693, 0x54DE5729, 0x23D967BF,
	0xB3667A2E, 0xC4614AB8, 0x5D681B02, 0x2A6F2B94, 0xB40BBE37, 0xC30C8EA1, 0x5A05DF1B, 0x2D02EF8D,
}

			local function crc32(buf: buffer, i: number, j: number)
				local code = 0xFFFFFFFF
				for k = i, j do
					code = bit32.bxor(
						bit32.rshift(code, 8),
						lookup[bit32.bxor(bit32.band(code, 0xFF), buffer.readu8(buf, k)) + 1]
					)
				end
				return bit32.bxor(code, 0xFFFFFFFF)
			end

			return crc32
		end
		function __BUNDLE.f(): typeof(__modImpl())
			local v = __BUNDLE.cache.f
			if not v then
				v = { c = __modImpl() }
				__BUNDLE.cache.f = v
			end
			return v.c
		end
	end
	do
		local function __modImpl()
			local MAX_BITS = 15

-- stylua: ignore
local LIT_LEN = {
	3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131,
	163, 195, 227, 258
}

-- stylua: ignore
local LIT_EXTRA = {
	1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
}

-- stylua: ignore
local DIST_OFF = {
	1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049,
	3073, 4097, 6145, 8193, 12289, 16385, 24577
}

-- stylua: ignore
local DIST_EXTRA = {
	0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13
}

-- stylua: ignore
local LEN_ORDER = {
	16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15
}

-- stylua: ignore
local FIXED_LIT = {
	8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,
	8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,
	8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,
	8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,
	8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9,
	9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9,
	9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9,
	9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9,
	7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 8, 8, 8, 8, 8, 8, 8, 8
}

			local WINDOW_LOOKAHEAD = 258
			local WINDOW_SEARCH = 0x8000 - WINDOW_LOOKAHEAD

			local MAX_CHAIN_NODES = 50_000
			local MAX_CHAIN_SEARCH = 12
			local MAX_MATCH_LENGTH = 96
			local DEFLATE_BLOCK_SIZE = 0x8000

			local function createHuffmanTable(
				lengths: { number }
			): (HuffmanTable__DARKLUA_TYPE_g, { number }, { number })
				local lengthCount = table.create(MAX_BITS, 0)
				lengthCount[0] = 0
				for _, length in lengths do
					if length > 0 then
						lengthCount[length] = (lengthCount[length] or 0) + 1
					end
				end

				local lastCode = 1
				local nextCode = table.create(MAX_BITS)
				for bits = 1, MAX_BITS do
					lastCode = bit32.lshift(lastCode + lengthCount[bits - 1], 1)
					nextCode[bits] = lastCode
				end

				local mapping = {}
				local codeValues = {}
				local codeLengths = {}
				for i, length in lengths do
					if length > 0 then
						mapping[nextCode[length]] = i - 1
						codeValues[i - 1] = bit32.extract(nextCode[length], 0, length)
						codeLengths[i - 1] = length
						nextCode[length] += 1
					end
				end

				return mapping, codeValues, codeLengths
			end

			local cachedLitValues = {}
			local cachedLitExtraValues = {}
			local cachedLitExtraBits = {}
			for length = 3, 258 do
				local idx
				for i = #LIT_LEN, 1, -1 do
					if length >= LIT_LEN[i] then
						idx = i
						break
					end
				end
				cachedLitValues[length] = 0x100 + idx
				cachedLitExtraValues[length] = length - LIT_LEN[idx]
				cachedLitExtraBits[length] = LIT_EXTRA[idx - 8] or 0
			end

			local cachedDistIndices = {}
			for distance = 1, 1024 do
				local distIdx
				for i = #DIST_OFF, 1, -1 do
					if distance >= DIST_OFF[i] then
						distIdx = i
						break
					end
				end
				cachedDistIndices[distance] = distIdx
			end

			local fixedLitTable, fixedLitCodeValues, fixedLitCodeLengths = createHuffmanTable(FIXED_LIT)
			local fixedDistTable, fixedDistCodeValues, fixedDistCodeLengths = createHuffmanTable(table.create(32, 5))

			local function getStoreSize(blockSize: number)
				return math.ceil(blockSize / DEFLATE_BLOCK_SIZE) * 5 + blockSize
			end

			local function getDistIdx(distance: number)
				return if distance < 1025
					then cachedDistIndices[distance]
					elseif distance < 1537 then 21
					elseif distance < 2049 then 22
					elseif distance < 3073 then 23
					elseif distance < 4097 then 24
					elseif distance < 6145 then 25
					elseif distance < 8193 then 26
					elseif distance < 12289 then 27
					elseif distance < 16385 then 28
					elseif distance < 24577 then 29
					else 30
			end

			local function adler32(input: buffer, offset: number, length: number): number
				local s0 = 1
				local s1 = 0
				local count = 0
				for i = offset, offset + length - 1 do
					s0 += buffer.readu8(input, i)
					s1 += s0
					count += 1
					if count == 8_400_000 then
						s0 %= 65521
						s1 %= 65521
						count = 0
					end
				end
				return bit32.bor(bit32.lshift(s1 % 65521, 16), s0 % 65521)
			end

			local function inflate(input: buffer, output: buffer): number
				local header0 = buffer.readu8(input, 0)
				local header1 = buffer.readu8(input, 1)
				assert(bit32.extract(header0, 0, 4) == 8, "invalid zlib comp method")
				assert(bit32.extract(header0, 4, 4) <= 7, "invalid zlib window size")
				assert(bit32.extract(header1, 5, 1) == 0, "preset dictionary is not allowed")
				assert(bit32.bor(bit32.lshift(header0, 8), header1) % 31 == 0, "zlib header sum mismatch")

				local readOffset = 2
				local readOffsetBit = 0

				local function readBit()
					local bit = bit32.extract(buffer.readu8(input, readOffset), readOffsetBit)
					readOffsetBit += 1
					if readOffsetBit == 8 then
						readOffsetBit = 0
						readOffset += 1
					end
					return bit
				end

				local function readBits(n: number)
					local bits = buffer.readbits(input, readOffset * 8 + readOffsetBit, n)
					readOffsetBit += n
					readOffset += bit32.rshift(readOffsetBit, 3)
					readOffsetBit = bit32.band(readOffsetBit, 0b111)
					return bits
				end

				local function readHuffmanTable(huffmanTable: HuffmanTable__DARKLUA_TYPE_g): number
					local code = 2 + readBit()
					while not huffmanTable[code] do
						code = 2 * code + readBit()
					end
					return huffmanTable[code]
				end

				local writeOffset = 0

				repeat
					local bfinal = readBit()
					local btype = readBits(2)
					assert(btype ~= 0b11, "reserved btype")

					if btype == 0b00 then
						if readOffsetBit > 0 then
							readOffset += 1
							readOffsetBit = 0
						end
						local len = buffer.readu16(input, readOffset)
						assert(bit32.bxor(len, buffer.readu16(input, readOffset + 2)) == 0xFFFF, "len ~= nlen")
						readOffset += 4
						buffer.copy(output, writeOffset, input, readOffset, len)
						writeOffset += len
						readOffset += len
					else
						local litTable = fixedLitTable
						local distTable = fixedDistTable

						if btype == 0b10 then
							local litsCount = readBits(5) + 257
							local distsCount = readBits(5) + 1
							local codesCount = readBits(4) + 4

							local codeLengths = table.create(19, 0)
							for i = 1, codesCount do
								codeLengths[LEN_ORDER[i] + 1] = readBits(3)
							end
							local codeLengthsTable = createHuffmanTable(codeLengths)

							local litLengths = table.create(litsCount)
							local litLength
							repeat
								local code = readHuffmanTable(codeLengthsTable)
								local repeatCount = 1
								if code <= 15 then
									litLength = code
								elseif code == 16 then
									repeatCount = readBits(2) + 3
								elseif code == 17 then
									litLength = 0
									repeatCount = readBits(3) + 3
								elseif code == 18 then
									litLength = 0
									repeatCount = readBits(7) + 11
								end
								for _ = 1, repeatCount do
									table.insert(litLengths, litLength)
								end
							until #litLengths >= litsCount
							litTable = createHuffmanTable(litLengths)

							local distLengths = table.create(distsCount)
							local distLength
							repeat
								local code = readHuffmanTable(codeLengthsTable)
								local repeatCount = 1
								if code <= 15 then
									distLength = code
								elseif code == 16 then
									repeatCount = readBits(2) + 3
								elseif code == 17 then
									distLength = 0
									repeatCount = readBits(3) + 3
								elseif code == 18 then
									distLength = 0
									repeatCount = readBits(7) + 11
								end
								for _ = 1, repeatCount do
									table.insert(distLengths, distLength)
								end
							until #distLengths >= distsCount
							distTable = createHuffmanTable(distLengths)
						end

						repeat
							local v = readHuffmanTable(litTable)
							if v < 0x100 then
								buffer.writeu8(output, writeOffset, v)
								writeOffset += 1
							elseif v > 0x100 then
								local len = LIT_LEN[v - 0x100]
								if v > 0x10C then
									len += readBits(LIT_EXTRA[v - 0x108])
								elseif v > 0x108 then
									len += readBit()
								end

								local d = readHuffmanTable(distTable)
								local dist = DIST_OFF[d + 1]
								if d > 5 then
									dist += readBits(DIST_EXTRA[d])
								elseif d > 3 then
									dist += readBit()
								end

								if len <= dist then
									buffer.copy(output, writeOffset, output, writeOffset - dist, len)
									writeOffset += len
								else
									repeat
										local size = math.min(len, dist)
										buffer.copy(output, writeOffset, output, writeOffset - dist, size)
										writeOffset += size
										len -= size
										dist += size
									until len == 0
								end
							end
						until v == 0x100
					end
				until bfinal == 0b1

				if readOffsetBit > 0 then
					readOffsetBit = 0
					readOffset += 1
				end

				assert(
					adler32(output, 0, buffer.len(output)) == bit32.byteswap(buffer.readu32(input, readOffset)),
					"adler-32 checksum mismatch"
				)

				return writeOffset
			end

			local function deflate(input: buffer): (buffer, number)
				local inputSize = buffer.len(input)
				local output = buffer.create(getStoreSize(inputSize) + 6)

				buffer.writeu16(output, 0, 0b01_0_11110_0111_1000)

				local writeOffset = 2
				local writeOffsetBits = 0

				local function writeBits(n: number, width: number)
					buffer.writebits(output, writeOffset * 8 + writeOffsetBits, width, n)
					writeOffsetBits += width
					writeOffset += bit32.rshift(writeOffsetBits, 3)
					writeOffsetBits = bit32.band(writeOffsetBits, 0b111)
				end

				local function writeHuffmanBits(n: number, w: number)
					n = bit32.bor(
						bit32.band(bit32.rshift(n, 1), 0x55555555),
						bit32.band(bit32.lshift(n, 1), 0xAAAAAAAA)
					)
					n = bit32.bor(
						bit32.band(bit32.rshift(n, 2), 0x33333333),
						bit32.band(bit32.lshift(n, 2), 0xCCCCCCCC)
					)
					n = bit32.bor(
						bit32.band(bit32.rshift(n, 4), 0x0F0F0F0F),
						bit32.band(bit32.lshift(n, 4), 0xF0F0F0F0)
					)
					n = bit32.bor(
						bit32.band(bit32.rshift(n, 8), 0x00FF00FF),
						bit32.band(bit32.lshift(n, 8), 0xFF00FF00)
					)
					n = bit32.bor(bit32.rshift(n, 16), bit32.lshift(n, 16))
					n = bit32.band(bit32.rshift(n, 32 - w), bit32.lshift(1, w) - 1)
					writeBits(n, w)
				end

				local function writeLitOrLen(value: number)
					writeHuffmanBits(fixedLitCodeValues[value], fixedLitCodeLengths[value])
				end

				local function writeBackRef(distance: number, length: number)
					writeLitOrLen(cachedLitValues[length])
					if length > 10 then
						writeBits(cachedLitExtraValues[length], cachedLitExtraBits[length])
					end
					local distIdx = getDistIdx(distance)
					writeHuffmanBits(fixedDistCodeValues[distIdx - 1], fixedDistCodeLengths[distIdx - 1])
					if distIdx > 3 then
						writeBits(distance - DIST_OFF[distIdx], DIST_EXTRA[distIdx - 1])
					end
				end

				local function getLitOrLenSize(value: number)
					return fixedLitCodeLengths[value]
				end

				local function getBackRefSize(distance: number, length: number)
					local distIdx = getDistIdx(distance)
					return getLitOrLenSize(cachedLitValues[length])
						+ cachedLitExtraBits[length]
						+ fixedDistCodeLengths[distIdx - 1]
						+ (DIST_EXTRA[distIdx - 1] or 0)
				end

				local offsets = {}
				local nexts = {}
				local heads = {}
				local nodeCount = 0

				local function insertNode(offset: number, nextIndex: number)
					nodeCount += 1
					offsets[nodeCount] = offset
					nexts[nodeCount] = nextIndex
					return nodeCount
				end

				local function clearTables()
					table.clear(offsets)
					table.clear(nexts)
					table.clear(heads)
					nodeCount = 0
				end

				for startReadOffset = 0, inputSize - 1, DEFLATE_BLOCK_SIZE do
					local huffmanSizeBits = 0

					local nextBlockReadOffset = math.min(inputSize, startReadOffset + DEFLATE_BLOCK_SIZE)
					local readOffset = startReadOffset

					local tokens: { vector } = {}
					while readOffset < nextBlockReadOffset - 3 do
						local hash = bit32.band(buffer.readu32(input, readOffset), 0xFFFFFF)
						local newNodeIndex = insertNode(readOffset, heads[hash] or 0)
						heads[hash] = newNodeIndex

						local bestLength = 0
						local bestOffset = -1

						local chainCount = 0
						local nodeIndex = nexts[newNodeIndex]
						while
							nodeIndex
							and (offsets[nodeIndex] or -math.huge) >= readOffset - WINDOW_SEARCH
							and chainCount < MAX_CHAIN_SEARCH
							and bestLength < MAX_MATCH_LENGTH
						do
							local searchLength = 3
							local searchOffset = offsets[nodeIndex]

							local exit = false
							local limit = math.min(nextBlockReadOffset, readOffset + WINDOW_LOOKAHEAD)
							if
								readOffset + bestLength < limit
								and buffer.readu8(input, searchOffset + bestLength)
									~= buffer.readu8(input, readOffset + bestLength)
							then
								exit = true
							end

							while
								not exit
								and searchLength < WINDOW_LOOKAHEAD
								and readOffset + searchLength < nextBlockReadOffset
								and buffer.readu8(input, searchOffset + searchLength)
									== buffer.readu8(input, readOffset + searchLength)
							do
								searchLength += 1
							end
							if searchLength > bestLength then
								bestLength = searchLength
								bestOffset = searchOffset
								if bestLength >= WINDOW_LOOKAHEAD then
									break
								end
							end
							nodeIndex = nexts[nodeIndex]
							chainCount += 1
						end

						if bestLength == 0 then
							local b = buffer.readu8(input, readOffset)
							huffmanSizeBits += getLitOrLenSize(b)
							table.insert(tokens, vector.create(0, b))
							readOffset += 1
						else
							huffmanSizeBits += getBackRefSize(readOffset - bestOffset, bestLength)
							table.insert(tokens, vector.create(1, readOffset - bestOffset, bestLength))
							for newOffset = readOffset + 1, math.min(readOffset + bestLength - 1, nextBlockReadOffset - 4) do
								local newHash = bit32.band(buffer.readu32(input, newOffset), 0xFFFFFF)
								heads[newHash] = insertNode(newOffset, heads[newHash] or 0)
							end
							readOffset += bestLength
						end
					end

					while readOffset < nextBlockReadOffset do
						local b = buffer.readu8(input, readOffset)
						huffmanSizeBits += getLitOrLenSize(b)
						table.insert(tokens, vector.create(0, b))
						readOffset += 1
					end

					huffmanSizeBits += getLitOrLenSize(0x100)
					table.insert(tokens, vector.create(0, 0x100))

					if nextBlockReadOffset == inputSize then
						writeBits(0b1, 1)
					else
						writeBits(0b0, 1)
					end

					local blockLength = nextBlockReadOffset - startReadOffset
					local fixedHuffmanSize = math.ceil(huffmanSizeBits / 8) + 1
					if fixedHuffmanSize < getStoreSize(blockLength) then
						writeBits(0b01, 2)
						for _, token in tokens do
							if token.x == 0 then
								writeLitOrLen(token.y)
							else
								writeBackRef(token.y, token.z)
							end
						end
					else
						writeBits(0b00, 2)
						if writeOffsetBits > 0 then
							writeOffset += 1
							writeOffsetBits = 0
						end
						buffer.writeu16(output, writeOffset, blockLength)
						buffer.writeu16(output, writeOffset + 2, bit32.bxor(0xFFFF, blockLength))
						buffer.copy(output, writeOffset + 4, input, startReadOffset, blockLength)
						writeOffset += 4 + blockLength
					end

					if nodeCount > MAX_CHAIN_NODES then
						clearTables()
					end
				end

				if writeOffsetBits > 0 then
					writeOffset += 1
				end

				local checksum = adler32(input, 0, buffer.len(input))
				buffer.writeu32(output, writeOffset, bit32.byteswap(checksum))

				return output, writeOffset + 4
			end

			return {
				inflate = inflate,
				deflate = deflate,
			}
		end
		function __BUNDLE.g(): typeof(__modImpl())
			local v = __BUNDLE.cache.g
			if not v then
				v = { c = __modImpl() }
				__BUNDLE.cache.g = v
			end
			return v.c
		end
	end
end
__BUNDLE.a()

local chunkReaders = __BUNDLE.e()
local crc32 = __BUNDLE.f()
local zlib = __BUNDLE.g()

local COLOR_TYPE_CHANNELS = {
	[0] = 1,
	[2] = 3,
	[3] = 1,
	[4] = 2,
	[6] = 4,
}

local INTERLACE_ROW_START = { 0, 0, 4, 0, 2, 0, 1 }
local INTERLACE_COL_START = { 0, 4, 0, 2, 0, 1, 0 }
local INTERLACE_ROW_INCR = { 8, 8, 8, 4, 4, 2, 2 }
local INTERLACE_COL_INCR = { 8, 8, 4, 4, 2, 2, 1 }

-- selene: allow(bad_string_escape)
local SIGNATURE = "\x89PNG\x0D\x0A\x1A\x0A"

type PNG = PNG__DARKLUA_TYPE_a

type DecodeOptions = {
	allowIncorrectCRC: boolean?,
}

type EncodeOptions = {
	width: number,
	height: number,
}

local function decode(buf: buffer, options: DecodeOptions?): PNG
	local bufLen = buffer.len(buf)
	assert(bufLen >= 8, "not a PNG")
	assert(buffer.readstring(buf, 0, 8) == SIGNATURE, "not a PNG")

	local chunks: { Chunk__DARKLUA_TYPE_b } = table.create(3)
	local offset = 8

	local skipCRC = options ~= nil and options.allowIncorrectCRC == true
	repeat
		local dataLength = bit32.byteswap(buffer.readu32(buf, offset))
		local chunkType = buffer.readstring(buf, offset + 4, 4)
		assert(string.match(chunkType, "%a%a%a%a"), `invalid chunk type {chunkType}`)

		local dataOffset = offset + 8
		local nextOffset = dataOffset + dataLength + 4
		assert(nextOffset <= bufLen, `EOF while reading {chunkType} chunk`)

		local chunkCode = bit32.byteswap(buffer.readu32(buf, nextOffset - 4))
		local expectCode = crc32(buf, offset + 4, nextOffset - 5)
		assert(skipCRC or chunkCode == expectCode, `incorrect checksum in {chunkType}`)

		table.insert(chunks, {
			type = chunkType,
			offset = dataOffset,
			length = dataLength,
		})
		offset = nextOffset
	until offset >= bufLen
	assert(offset == bufLen, "trailing data in file")

	for _, chunk in chunks do
		local t = chunk.type
		if bit32.extract(string.byte(t, 1, 1), 5) == 0 then
			if t ~= "IHDR" and t ~= "IDAT" and t ~= "PLTE" and t ~= "IEND" then
				error(`unhandled critical chunk {t}`)
			end
		end
	end

	local header: IHDRChunk__DARKLUA_TYPE_c
	local headerChunk = chunks[1]
	assert(headerChunk.type == "IHDR", "first chunk must be IHDR")
	for i = 2, #chunks do
		assert(chunks[i].type ~= "IHDR", "multiple IHDR chunks are not allowed")
	end
	header = chunkReaders.IHDR(buf, headerChunk)

	local dataChunkIndex0 = -1
	local dataChunkIndex1 = -1
	local compressedDataLength = 0
	for i, chunk in chunks do
		if chunk.type == "IDAT" then
			if dataChunkIndex0 < 0 then
				dataChunkIndex0 = i
			else
				assert(i == dataChunkIndex1 + 1, "multiple IDAT chunks must be consecutive")
			end
			dataChunkIndex1 = i
			compressedDataLength += chunk.length
		end
	end
	assert(dataChunkIndex0 > 0, "no IDAT chunks")
	assert(compressedDataLength > 0, "no image data in IDAT chunks")

	local palette: PLTEChunk__DARKLUA_TYPE_e?
	local paletteChunkIndex = -1
	for i, chunk in chunks do
		if chunk.type == "PLTE" then
			assert(not palette, "multiple PLTE chunks are not allowed")
			assert(i < dataChunkIndex0, "PLTE not allowed after IDAT chunks")
			assert(header.colorType ~= 0 and header.colorType ~= 4, "PLTE not allowed for color type")
			palette = chunkReaders.PLTE(buf, chunk, header)
			paletteChunkIndex = i
		end
	end
	if header.colorType == 3 then
		assert(palette ~= nil, "color type requires a PLTE chunk")
	end

	local transparencyData: tRNSChunk__DARKLUA_TYPE_f?
	for i, chunk in chunks do
		if chunk.type == "tRNS" then
			assert(transparencyData == nil, "multiple tRNS chunks are not allowed")
			assert(i < dataChunkIndex0, "tRNS not allowed after IDAT chunks")
			assert(not palette or i > paletteChunkIndex, "tRNS must be after PLTE")
			assert(header.colorType ~= 4 and header.colorType ~= 6, "tRNS not allowed for color type")
			transparencyData = chunkReaders.tRNS(buf, chunk, header, palette)
		end
	end

	local finalChunk = chunks[#chunks]
	assert(finalChunk.type == "IEND", "final chunk must be IEND")
	assert(finalChunk.length == 0, "IEND chunk must be empty")
	for i = 2, #chunks - 1 do
		assert(chunks[i].type ~= "IEND", "multiple IEND chunks are not allowed")
	end

	local compressedData = buffer.create(compressedDataLength)
	local compressedOffset = 0
	for _, chunk in chunks do
		if chunk.type == "IDAT" then
			buffer.copy(compressedData, compressedOffset, buf, chunk.offset, chunk.length)
			compressedOffset += chunk.length
		end
	end

	local width = header.width
	local height = header.height
	local bitDepth = header.bitDepth
	local colorType = header.colorType
	local channels = COLOR_TYPE_CHANNELS[colorType]

	local rawSize = 0
	if not header.interlaced then
		rawSize = height * (math.ceil(width * channels * bitDepth / 8) + 1)
	else
		for i = 1, 7 do
			local w = math.ceil((width - INTERLACE_COL_START[i]) / INTERLACE_COL_INCR[i])
			local h = math.ceil((height - INTERLACE_ROW_START[i]) / INTERLACE_ROW_INCR[i])
			if w > 0 and h > 0 then
				local scanlineSize = math.ceil(w * channels * bitDepth / 8) + 1
				rawSize += h * scanlineSize
			end
		end
	end

	local paletteColors
	if palette then
		paletteColors = palette.colors
	end

	local rescale
	if colorType ~= 3 and bitDepth < 8 then
		rescale = 0xFF / (2 ^ bitDepth - 1)
	end

	local bpp = math.ceil(channels * bitDepth / 8)
	local defaultAlpha = 2 ^ bitDepth - 1

	local idx = 0
	local working = buffer.create(rawSize)
	local inflatedSize = zlib.inflate(compressedData, working)
	assert(inflatedSize == rawSize, "decompressed data size mismatch")

	local rgba8 = buffer.create(width * height * 4)

	local alphaGray = if transparencyData then transparencyData.gray else -1
	local alphaRed = if transparencyData then transparencyData.red else -1
	local alphaGreen = if transparencyData then transparencyData.green else -1
	local alphaBlue = if transparencyData then transparencyData.blue else -1

	local function pass(sx: number, sy: number, dx: number, dy: number)
		local w = math.ceil((width - sx) / dx)
		local h = math.ceil((height - sy) / dy)
		if w < 1 or h < 1 then
			return
		end

		local scanlineSize = math.ceil(w * channels * bitDepth / 8)
		local newIdx = idx

		for y = 1, h do
			local rowFilter = buffer.readu8(working, idx)
			idx += 1

			if rowFilter == 0 or (rowFilter == 2 and y == 1) then
				idx += scanlineSize
			elseif rowFilter == 1 then
				for x = 1, scanlineSize do
					local sub = if x <= bpp then 0 else buffer.readu8(working, idx - bpp)
					local value = bit32.band(buffer.readu8(working, idx) + sub, 0xFF)
					buffer.writeu8(working, idx, value)
					idx += 1
				end
			elseif rowFilter == 2 then
				for _ = 1, scanlineSize do
					local up = buffer.readu8(working, idx - scanlineSize - 1)
					local value = bit32.band(buffer.readu8(working, idx) + up, 0xFF)
					buffer.writeu8(working, idx, value)
					idx += 1
				end
			elseif rowFilter == 3 then
				for x = 1, scanlineSize do
					local sub = if x <= bpp then 0 else buffer.readu8(working, idx - bpp)
					local up = if y == 1 then 0 else buffer.readu8(working, idx - scanlineSize - 1)
					local value = bit32.band(buffer.readu8(working, idx) + bit32.rshift(sub + up, 1), 0xFF)
					buffer.writeu8(working, idx, value)
					idx += 1
				end
			elseif rowFilter == 4 then
				for x = 1, scanlineSize do
					local sub = if x <= bpp then 0 else buffer.readu8(working, idx - bpp)
					local up = if y == 1 then 0 else buffer.readu8(working, idx - scanlineSize - 1)
					local corner = if x <= bpp or y == 1
						then 0
						else buffer.readu8(working, idx - scanlineSize - bpp - 1)
					local p0 = math.abs(up - corner)
					local p1 = math.abs(sub - corner)
					local p2 = math.abs(sub + up - 2 * corner)
					local paeth = if p0 <= p1 and p0 <= p2 then sub elseif p1 <= p2 then up else corner
					local value = bit32.band(buffer.readu8(working, idx) + paeth, 0xFF)
					buffer.writeu8(working, idx, value)
					idx += 1
				end
			else
				error("invalid row filter")
			end
		end

		local bit = 8
		local function readValue()
			local b = buffer.readu8(working, newIdx)
			if bitDepth < 8 then
				b = bit32.extract(b, bit - bitDepth, bitDepth)
				bit -= bitDepth
				if bit == 0 then
					bit = 8
					newIdx += 1
				end
			elseif bitDepth == 8 then
				newIdx += 1
			else
				b = bit32.bor(bit32.lshift(b, 8), buffer.readu8(working, newIdx + 1))
				newIdx += 2
			end
			return b
		end

		for y = 1, h do
			newIdx += 1
			if bit < 8 then
				bit = 8
				newIdx += 1
			end

			for x = 1, w do
				local r, g, b, a

				if colorType == 0 then
					local gray = readValue()
					r = gray
					g = gray
					b = gray
					a = if gray == alphaGray then 0 else defaultAlpha
				elseif colorType == 2 then
					r = readValue()
					g = readValue()
					b = readValue()
					a = if r == alphaRed and g == alphaGreen and b == alphaBlue then 0 else defaultAlpha
				elseif colorType == 3 then
					local color = paletteColors[readValue() + 1]
					r = color.r
					g = color.g
					b = color.b
					a = color.a
				elseif colorType == 4 then
					local gray = readValue()
					r = gray
					g = gray
					b = gray
					a = readValue()
				elseif colorType == 6 then
					r = readValue()
					g = readValue()
					b = readValue()
					a = readValue()
				end

				local py = sy + (y - 1) * dy
				local px = sx + (x - 1) * dx
				local i = (py * width + px) * 4

				if rescale then
					r = math.round(r * rescale)
					g = math.round(g * rescale)
					b = math.round(b * rescale)
					a = math.round(a * rescale)
				elseif bitDepth == 16 then
					r = bit32.rshift(r, 8)
					g = bit32.rshift(g, 8)
					b = bit32.rshift(b, 8)
					a = bit32.rshift(a, 8)
				end

				buffer.writeu32(rgba8, i, bit32.bor(bit32.lshift(a, 24), bit32.lshift(b, 16), bit32.lshift(g, 8), r))
			end
		end
	end

	if not header.interlaced then
		pass(0, 0, 1, 1)
	else
		for i = 1, 7 do
			pass(INTERLACE_COL_START[i], INTERLACE_ROW_START[i], INTERLACE_COL_INCR[i], INTERLACE_ROW_INCR[i])
		end
	end

	local function readPixel(x: number, y: number)
		assert(x >= 1 and x <= width and y >= 1 and y <= height, "pixel out of range")

		local i = ((y - 1) * width + x - 1) * 4
		return buffer.readu8(rgba8, i),
			buffer.readu8(rgba8, i + 1),
			buffer.readu8(rgba8, i + 2),
			buffer.readu8(rgba8, i + 3)
	end

	return {
		width = width,
		height = height,
		pixels = rgba8,
		readPixel = readPixel,
	}
end

local function encode(pixels: buffer, options: EncodeOptions): buffer
	local width = options.width
	local height = options.height

	local dataSize = buffer.len(pixels)
	local expectSize = width * height * 4
	assert(dataSize == expectSize, `expected {expectSize} bytes, got {dataSize} bytes`)

	local imageDataRowSize = width * 4 + 1
	local imageData = buffer.create(height * imageDataRowSize)
	for row = 0, height - 1 do
		local sourceOffset = row * width * 4
		local targetOffset = row * imageDataRowSize
		buffer.writeu8(imageData, targetOffset, 0)
		buffer.copy(imageData, targetOffset + 1, pixels, sourceOffset, 4 * width)
	end

	local imageDataDeflated, imageDataDeflatedLength = zlib.deflate(imageData)
	local outputLength = 8 + 25 + (8 + imageDataDeflatedLength + 4) + 12

	local output = buffer.create(outputLength)
	buffer.writestring(output, 0, SIGNATURE)

	buffer.writeu32(output, 8, bit32.byteswap(13))
	buffer.writestring(output, 12, "IHDR")
	buffer.writeu32(output, 16, bit32.byteswap(width))
	buffer.writeu32(output, 20, bit32.byteswap(height))
	buffer.writeu8(output, 24, 8)
	buffer.writeu8(output, 25, 6)
	buffer.writeu8(output, 26, 0)
	buffer.writeu8(output, 27, 0)
	buffer.writeu8(output, 28, 0)
	buffer.writeu32(output, 29, bit32.byteswap(crc32(output, 12, 28)))

	buffer.writeu32(output, 33, bit32.byteswap(imageDataDeflatedLength))
	buffer.writestring(output, 37, "IDAT")
	buffer.copy(output, 41, imageDataDeflated, 0, imageDataDeflatedLength)
	local x = 41 + imageDataDeflatedLength
	buffer.writeu32(output, x, bit32.byteswap(crc32(output, 37, x - 1)))

	buffer.writeu32(output, x + 4, 0)
	buffer.writestring(output, x + 8, "IEND")
	buffer.writeu32(output, x + 12, 0x826042AE)

	return output
end

return {
	decode = decode,
	encode = encode,
}

end)()
-- ===== end png-luau (PNG.decode(buf) -> {width,height,pixels(RGBA buffer)}) =====

local FAL_BASE = "https://queue.fal.run"
local FAL_STORAGE_INITIATE = "https://rest.fal.ai/storage/upload/initiate?storage_type=fal-cdn-v3"
local TEXT_MODEL = "tripo3d/p1/text-to-3d"
local IMAGE_MODEL = "tripo3d/p1/image-to-3d"
-- Image gen/edit: two tiers (Fast = z-image turbo, Quality = nano-banana 2)
local IMAGE_GEN_MODEL_FAST = "fal-ai/z-image/turbo"
local IMAGE_GEN_MODEL_QUALITY = "fal-ai/nano-banana-2"
local IMAGE_EDIT_MODEL_FAST = "fal-ai/z-image/turbo/image-to-image"
local IMAGE_EDIT_MODEL_QUALITY = "fal-ai/nano-banana-2/edit"
local PATINA_MATERIAL_MODEL = "fal-ai/patina/material" -- text → tiling PBR material (PNG)
local PATINA_FROM_IMAGE_MODEL = "fal-ai/patina" -- image → PBR maps (PNG)
-- Video: two tiers (Fast = LTX-2.3, Quality = Seedance 2.0). Output URL at result.video.url.
-- Fast/LTX has no 720p (floor 1080p → Roblox downscales to its 720p cap); Quality/Seedance defaults to 720p.
local VIDEO_T2V_FAST = "fal-ai/ltx-2.3/text-to-video/fast"
local VIDEO_I2V_FAST = "fal-ai/ltx-2.3/image-to-video/fast"
local VIDEO_T2V_QUALITY = "bytedance/seedance-2.0/text-to-video"
local VIDEO_I2V_QUALITY = "bytedance/seedance-2.0/image-to-video"
local DEFAULT_FACE_LIMIT = 9000
local POLL_INTERVAL = 2
local MAX_IMAGE_BYTES = 4 * 1024 * 1024

-- ============================================================
-- Storage (plugin:SetSetting - plaintext on disk, BYO key only)
-- ============================================================
local function getKey()
	return plugin:GetSetting("fal_key") or ""
end
local function setKey(k)
	plugin:SetSetting("fal_key", k)
end

-- ============================================================
-- fal client
-- ============================================================
local function authHeaders()
	local key = getKey()
	if key == "" then
		error("FAL_KEY not set - paste it into the widget and click Save key.")
	end
	return {
		["Authorization"] = "Key " .. key,
		["Content-Type"] = "application/json",
		["Accept"] = "application/json",
	}
end

local function falSubmit(model, payload)
	local res = HttpService:RequestAsync({
		Url = FAL_BASE .. "/" .. model,
		Method = "POST",
		Headers = authHeaders(),
		Body = HttpService:JSONEncode(payload),
	})
	if not res.Success then
		error(string.format("submit %d %s - %s", res.StatusCode, res.StatusMessage, res.Body))
	end
	return HttpService:JSONDecode(res.Body)
end

local function falGet(url)
	local key = getKey()
	if key == "" then
		error("FAL_KEY not set.")
	end
	-- GETs only send Authorization; no Content-Type since there's no body.
	local res = HttpService:RequestAsync({
		Url = url,
		Method = "GET",
		Headers = {
			["Authorization"] = "Key " .. key,
			["Accept"] = "application/json",
		},
	})
	if not res.Success then
		error(string.format("GET %s → %d %s\nbody: %s", url, res.StatusCode, res.StatusMessage, res.Body or "(empty)"))
	end
	return HttpService:JSONDecode(res.Body)
end

local function falRunJob(model, payload, onLog)
	local sub = falSubmit(model, payload)
	local requestId = sub.request_id
	-- fal's submit response includes the canonical URLs to poll. For
	-- namespaced apps (e.g. tripo3d/p1/text-to-3d) the status path drops the
	-- leaf segment, so always trust these URLs over hand-built ones.
	local statusUrl = sub.status_url
	local responseUrl = sub.response_url
	if not statusUrl or not responseUrl then
		error("submit response missing status_url/response_url: " .. HttpService:JSONEncode(sub))
	end
	onLog("queued: " .. tostring(requestId))
	local lastStatus = nil
	while true do
		task.wait(POLL_INTERVAL)
		local st = falGet(statusUrl)
		if st.status ~= lastStatus then
			onLog("status: " .. tostring(st.status))
			lastStatus = st.status
		end
		if st.status == "COMPLETED" then
			return falGet(responseUrl)
		elseif st.status == "FAILED" or st.status == "CANCELLED" or st.status == "ERROR" then
			error("job " .. tostring(st.status) .. ": " .. HttpService:JSONEncode(st))
		end
	end
end

-- ============================================================
-- fal storage - initiate + PUT, returns a public file URL.
-- Mirrors what @fal-ai/client does in storage.ts.
-- ============================================================
local function redact(s)
	-- Strip key=… fragments from error bodies before printing.
	if not s then return "" end
	return (string.gsub(s, "[Kk][Ee][Yy]=[%w%-_]+", "key=<redacted>"))
end

local function falStorageUpload(bytes, fileName, mime)
	local key = getKey()
	if key == "" then
		error("FAL_KEY not set.")
	end

	-- 1. POST /storage/upload/initiate → { file_url, upload_url }
	local initRes = HttpService:RequestAsync({
		Url = FAL_STORAGE_INITIATE,
		Method = "POST",
		Headers = {
			["Authorization"] = "Key " .. key,
			["Content-Type"] = "application/json",
			["Accept"] = "application/json",
		},
		Body = HttpService:JSONEncode({
			content_type = mime,
			file_name = fileName,
		}),
	})
	if not initRes.Success then
		error(string.format("storage initiate %d %s - %s", initRes.StatusCode, initRes.StatusMessage, redact(initRes.Body)))
	end
	local init = HttpService:JSONDecode(initRes.Body)
	local uploadUrl = init.upload_url
	local fileUrl = init.file_url
	if not uploadUrl or not fileUrl then
		error("storage initiate missing upload_url/file_url: " .. redact(initRes.Body))
	end

	-- 2. PUT bytes to upload_url (signed URL - no auth header needed).
	local putRes = HttpService:RequestAsync({
		Url = uploadUrl,
		Method = "PUT",
		Headers = {
			["Content-Type"] = mime,
		},
		Body = bytes,
	})
	if not putRes.Success then
		error(string.format("storage PUT %d %s", putRes.StatusCode, putRes.StatusMessage))
	end

	return fileUrl
end

-- ============================================================
-- Result parsing
-- ============================================================
local function extractGlbUrl(result)
	if result.model_mesh and result.model_mesh.url and result.model_mesh.url ~= "" then
		return result.model_mesh.url
	end
	if result.model_urls then
		if result.model_urls.glb and result.model_urls.glb.url then
			return result.model_urls.glb.url
		end
		if result.model_urls.pbr_model and result.model_urls.pbr_model.url then
			return result.model_urls.pbr_model.url
		end
	end
	return nil
end

-- ============================================================
-- Image decode → EditableImage (for in-Studio preview of fal images)
-- Fetch a PNG from a URL, decode it via the inlined png-luau, return a
-- live EditableImage. Kept referenced so it isn't GC'd while displayed.
-- ============================================================
local imageKeepAlive = {}
local function urlToEditableImage(url)
	local res = HttpService:RequestAsync({ Url = url, Method = "GET" })
	if not res.Success then
		error(string.format("download %d %s", res.StatusCode, tostring(res.StatusMessage)))
	end
	local img = PNG.decode(buffer.fromstring(res.Body)) -- { width, height, pixels (RGBA buffer) }
	local size = Vector2.new(img.width, img.height)
	local ei = AssetService:CreateEditableImage({ Size = size })
	if not ei then
		error(string.format("CreateEditableImage nil (%dx%d - over cap?)", img.width, img.height))
	end
	ei:WritePixelsBuffer(Vector2.zero, size, img.pixels)
	table.insert(imageKeepAlive, ei)
	return ei, img.width, img.height
end

-- ============================================================
-- UI
-- ============================================================
local TOOLBAR = plugin:CreateToolbar("fal")
local BUTTON = TOOLBAR:CreateButton("falgen", "fal genmedia for Roblox Studio", "")
BUTTON.ClickableWhenViewportHidden = true

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float, false, false, 440, 680, 360, 520
)
local widget = plugin:CreateDockWidgetPluginGui("falgen.widget", widgetInfo)
widget.Title = "fal · genmedia"
widget.Name = "falgen"

BUTTON.Click:Connect(function() widget.Enabled = not widget.Enabled end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function() BUTTON:SetActive(widget.Enabled) end)

-- ---- palette ----
local COL_BG = Color3.fromRGB(40, 40, 40)
local COL_TABBAR = Color3.fromRGB(30, 30, 30)
local COL_ON = Color3.fromRGB(70, 100, 200)
local COL_OFF = Color3.fromRGB(52, 52, 52)
local COL_ACCENT = Color3.fromRGB(120, 80, 190)

-- ---- root layout: tab bar (top) + content (middle) + status (bottom) ----
local TAB_H, STATUS_H = 34, 110

local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, 0, 0, TAB_H)
tabBar.BackgroundColor3 = COL_TABBAR
tabBar.BorderSizePixel = 0
tabBar.Parent = widget
do
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = tabBar
end

local content = Instance.new("Frame")
content.Position = UDim2.new(0, 0, 0, TAB_H)
content.Size = UDim2.new(1, 0, 1, -(TAB_H + STATUS_H))
content.BackgroundColor3 = COL_BG
content.BorderSizePixel = 0
content.Parent = widget

local statusBar = Instance.new("Frame")
statusBar.Position = UDim2.new(0, 0, 1, -STATUS_H)
statusBar.Size = UDim2.new(1, 0, 0, STATUS_H)
statusBar.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
statusBar.BorderSizePixel = 0
statusBar.Parent = widget

local statusBox = Instance.new("TextLabel")
statusBox.Size = UDim2.new(1, 0, 1, 0)
statusBox.BackgroundTransparency = 1
statusBox.TextColor3 = Color3.fromRGB(200, 200, 200)
statusBox.Font = Enum.Font.Code
statusBox.TextSize = 12
statusBox.TextXAlignment = Enum.TextXAlignment.Left
statusBox.TextYAlignment = Enum.TextYAlignment.Bottom
statusBox.TextWrapped = true
statusBox.RichText = false
statusBox.Text = "Idle."
statusBox.Parent = statusBar
do
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, 6); p.PaddingBottom = UDim.new(0, 6)
	p.PaddingLeft = UDim.new(0, 10); p.PaddingRight = UDim.new(0, 10)
	p.Parent = statusBox
end

local function setStatus(text) statusBox.Text = text; print("[falgen] " .. text) end
local function appendStatus(text) statusBox.Text = statusBox.Text .. "\n" .. text; print("[falgen] " .. text) end

-- ---- tabs ----
local TAB_NAMES = { "Settings", "Image", "3D", "Material", "Video" }
local tabFrames, tabButtons = {}, {}
local activeBuildParent = nil

local function showTab(name)
	for n, f in pairs(tabFrames) do f.Visible = (n == name) end
	for n, b in pairs(tabButtons) do b.BackgroundColor3 = (n == name) and COL_ON or COL_OFF end
end

local function makeTab(name, n)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1 / #TAB_NAMES, 0, 1, 0)
	b.BackgroundColor3 = COL_OFF
	b.BorderSizePixel = 0
	b.TextColor3 = Color3.fromRGB(235, 235, 235)
	b.Font = Enum.Font.SourceSansSemibold
	b.TextSize = 14
	b.Text = name
	b.AutoButtonColor = true
	b.LayoutOrder = n
	b.Parent = tabBar
	b.MouseButton1Click:Connect(function() showTab(name) end)
	tabButtons[name] = b

	local f = Instance.new("ScrollingFrame")
	f.Size = UDim2.new(1, 0, 1, 0)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.ScrollBarThickness = 6
	f.AutomaticCanvasSize = Enum.AutomaticSize.Y
	f.CanvasSize = UDim2.new(0, 0, 0, 0)
	f.Visible = false
	f.Parent = content
	local l = Instance.new("UIListLayout"); l.Padding = UDim.new(0, 8); l.SortOrder = Enum.SortOrder.LayoutOrder; l.Parent = f
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, 12); p.PaddingBottom = UDim.new(0, 12); p.PaddingLeft = UDim.new(0, 12); p.PaddingRight = UDim.new(0, 12); p.Parent = f
	tabFrames[name] = f
	return f
end

for i, n in ipairs(TAB_NAMES) do makeTab(n, i) end

-- ---- maximize overlay (click any image preview to enlarge) ----
local maximizeOverlay = Instance.new("Frame")
maximizeOverlay.Size = UDim2.new(1, 0, 1, 0)
maximizeOverlay.BackgroundColor3 = Color3.fromRGB(8, 8, 8)
maximizeOverlay.BackgroundTransparency = 0.06
maximizeOverlay.BorderSizePixel = 0
maximizeOverlay.ZIndex = 50
maximizeOverlay.Visible = false
maximizeOverlay.Parent = widget

-- full-area button behind the image → click anywhere to dismiss
local maximizeBackdrop = Instance.new("TextButton")
maximizeBackdrop.Size = UDim2.new(1, 0, 1, 0)
maximizeBackdrop.BackgroundTransparency = 1
maximizeBackdrop.Text = ""
maximizeBackdrop.AutoButtonColor = false
maximizeBackdrop.ZIndex = 50
maximizeBackdrop.Parent = maximizeOverlay

local modalImg = Instance.new("ImageLabel")
modalImg.Size = UDim2.new(1, -24, 1, -56)
modalImg.Position = UDim2.new(0, 12, 0, 44)
modalImg.BackgroundTransparency = 1
modalImg.ScaleType = Enum.ScaleType.Fit
modalImg.ZIndex = 51
modalImg.Parent = maximizeOverlay

local closeMaxBtn = Instance.new("TextButton")
closeMaxBtn.Size = UDim2.new(0, 90, 0, 28)
closeMaxBtn.Position = UDim2.new(1, -100, 0, 8)
closeMaxBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
closeMaxBtn.TextColor3 = Color3.fromRGB(240, 240, 240)
closeMaxBtn.Font = Enum.Font.SourceSansSemibold
closeMaxBtn.TextSize = 14
closeMaxBtn.Text = "✕ Close"
closeMaxBtn.ZIndex = 52
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 4); c.Parent = closeMaxBtn end
closeMaxBtn.Parent = maximizeOverlay

local function closeMaximize() maximizeOverlay.Visible = false end
maximizeBackdrop.MouseButton1Click:Connect(closeMaximize)
closeMaxBtn.MouseButton1Click:Connect(closeMaximize)

-- assign an image Content to a preview (ImageContent, falling back to Image) + remember it for enlarge
local previewContent = {}
local function assignImage(target, content)
	if not pcall(function() target.ImageContent = content end) then pcall(function() target.Image = content end) end
	previewContent[target] = content
end

local function openMaximize(srcBtn)
	local content = previewContent[srcBtn]
	if not content then return end -- nothing to show yet
	if not pcall(function() modalImg.ImageContent = content end) then pcall(function() modalImg.Image = content end) end
	maximizeOverlay.Visible = true
end

-- ---- build helpers (parent into whichever tab is being built) ----
local order = 0
local function nextOrder() order = order + 1; return order end

local function header(text)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 0, 22); lbl.BackgroundTransparency = 1
	lbl.TextColor3 = Color3.fromRGB(240, 240, 240); lbl.Font = Enum.Font.SourceSansBold
	lbl.TextSize = 16; lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Text = text; lbl.LayoutOrder = nextOrder(); lbl.Parent = activeBuildParent
	return lbl
end
local function muted(text, height)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 0, height or 30); lbl.BackgroundTransparency = 1
	lbl.TextColor3 = Color3.fromRGB(160, 160, 160); lbl.Font = Enum.Font.SourceSans
	lbl.TextSize = 13; lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextYAlignment = Enum.TextYAlignment.Top; lbl.TextWrapped = true
	lbl.Text = text; lbl.LayoutOrder = nextOrder(); lbl.Parent = activeBuildParent
	return lbl
end
local function divider()
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, 0, 0, 1); f.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
	f.BorderSizePixel = 0; f.LayoutOrder = nextOrder(); f.Parent = activeBuildParent
	return f
end
local function textBox(placeholder, height, multi)
	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, 0, 0, height or 28); box.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
	box.TextColor3 = Color3.fromRGB(240, 240, 240); box.Text = ""
	box.PlaceholderText = placeholder or ""; box.PlaceholderColor3 = Color3.fromRGB(110, 110, 110)
	box.Font = Enum.Font.SourceSans; box.TextSize = 14; box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextYAlignment = multi and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center
	box.MultiLine = multi == true; box.TextWrapped = multi == true; box.LayoutOrder = nextOrder()
	local p = Instance.new("UIPadding"); p.PaddingLeft = UDim.new(0,8); p.PaddingRight = UDim.new(0,8); p.PaddingTop = UDim.new(0,4); p.PaddingBottom = UDim.new(0,4); p.Parent = box
	local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(60,60,60); stroke.Parent = box
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,4); corner.Parent = box
	box.Parent = activeBuildParent
	return box
end
local function button(text, color)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, 32); btn.BackgroundColor3 = color or COL_ON
	btn.TextColor3 = Color3.fromRGB(255,255,255); btn.Font = Enum.Font.SourceSansSemibold
	btn.TextSize = 14; btn.Text = text; btn.AutoButtonColor = true; btn.LayoutOrder = nextOrder()
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,4); corner.Parent = btn
	btn.Parent = activeBuildParent
	return btn
end
-- inline dropdown: a header that expands a list of options downward (pushes items below).
-- opening one collapses any other open dropdown. onSelect(value) fires on pick and on rebuild.
-- returns a handle with .rebuild(newOptions) so the option list can change with the quality tier.
local dropdownClosers = {}
local function dropdown(labelText, options, onSelect)
	local OPTION_H, ROW_BG = 26, Color3.fromRGB(26, 26, 26)
	local current, open, rowCount = nil, false, 0

	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(1, 0, 0, 32); holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0; holder.ClipsDescendants = true
	holder.LayoutOrder = nextOrder(); holder.Parent = activeBuildParent

	local head = Instance.new("TextButton")
	head.Size = UDim2.new(1, 0, 0, 32); head.BackgroundColor3 = COL_OFF; head.AutoButtonColor = true
	head.TextColor3 = Color3.fromRGB(235, 235, 235); head.Font = Enum.Font.SourceSansSemibold
	head.TextSize = 14; head.TextXAlignment = Enum.TextXAlignment.Left; head.Text = ""
	do local p = Instance.new("UIPadding"); p.PaddingLeft = UDim.new(0,10); p.PaddingRight = UDim.new(0,26); p.Parent = head end
	do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,4); c.Parent = head end
	head.Parent = holder

	local caret = Instance.new("TextLabel")
	caret.AnchorPoint = Vector2.new(1, 0); caret.Position = UDim2.new(1, -10, 0, 0); caret.Size = UDim2.new(0, 14, 0, 32)
	caret.BackgroundTransparency = 1; caret.TextColor3 = Color3.fromRGB(170, 170, 170)
	caret.Font = Enum.Font.SourceSansBold; caret.TextSize = 14; caret.Text = "▾"; caret.ZIndex = 2; caret.Parent = holder

	local list = Instance.new("Frame")
	list.Position = UDim2.new(0, 0, 0, 35); list.Size = UDim2.new(1, 0, 0, 0)
	list.BackgroundColor3 = ROW_BG; list.BorderSizePixel = 0; list.Visible = false
	do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,4); c.Parent = list end
	do local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(60,60,60); s.Parent = list end
	do local l = Instance.new("UIListLayout"); l.SortOrder = Enum.SortOrder.LayoutOrder; l.Parent = list end
	list.Parent = holder

	local function highlight()
		for _, r in ipairs(list:GetChildren()) do
			if r:IsA("TextButton") then r.BackgroundColor3 = (r.Text == current) and COL_ON or ROW_BG end
		end
	end
	local function collapse() open = false; list.Visible = false; holder.Size = UDim2.new(1, 0, 0, 32); caret.Text = "▾" end
	dropdownClosers[#dropdownClosers + 1] = collapse
	local function expand()
		for _, c in ipairs(dropdownClosers) do c() end
		open = true; list.Visible = true; caret.Text = "▴"
		holder.Size = UDim2.new(1, 0, 0, 35 + rowCount * OPTION_H + 2)
	end
	head.MouseButton1Click:Connect(function() if open then collapse() else expand() end end)

	local function setValue(v, fire)
		current = v; head.Text = labelText .. ":   " .. tostring(current); highlight()
		if fire and onSelect then onSelect(current) end
	end
	local function populate(opts)
		for _, r in ipairs(list:GetChildren()) do if r:IsA("TextButton") then r:Destroy() end end
		rowCount = #opts
		for i, opt in ipairs(opts) do
			local row = Instance.new("TextButton")
			row.Size = UDim2.new(1, 0, 0, OPTION_H); row.AutoButtonColor = true; row.BorderSizePixel = 0
			row.BackgroundColor3 = ROW_BG; row.TextColor3 = Color3.fromRGB(225, 225, 225)
			row.Font = Enum.Font.SourceSans; row.TextSize = 14; row.TextXAlignment = Enum.TextXAlignment.Left
			row.Text = opt; row.LayoutOrder = i
			do local p = Instance.new("UIPadding"); p.PaddingLeft = UDim.new(0,12); p.Parent = row end
			row.Parent = list
			row.MouseButton1Click:Connect(function() collapse(); setValue(opt, true) end)
		end
		list.Size = UDim2.new(1, 0, 0, rowCount * OPTION_H)
		local keep = nil
		for _, o in ipairs(opts) do if o == current then keep = o end end
		setValue(keep or opts[1], true) -- clamp to a valid value, syncing external state
	end

	populate(options)
	return { rebuild = function(opts) collapse(); populate(opts) end }
end
local function imagePreview(height)
	local img = Instance.new("ImageButton")
	img.Size = UDim2.new(1, 0, 0, height or 180); img.BackgroundColor3 = Color3.fromRGB(24,24,24)
	img.AutoButtonColor = false; img.BorderSizePixel = 0; img.ScaleType = Enum.ScaleType.Fit; img.LayoutOrder = nextOrder()
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,4); c.Parent = img
	-- enlarge affordance (top-right)
	local badge = Instance.new("TextLabel")
	badge.Size = UDim2.new(0, 24, 0, 20); badge.Position = UDim2.new(1, -28, 0, 4)
	badge.BackgroundColor3 = Color3.fromRGB(0,0,0); badge.BackgroundTransparency = 0.35
	badge.TextColor3 = Color3.fromRGB(240,240,240); badge.Font = Enum.Font.SourceSansBold
	badge.TextSize = 15; badge.Text = "⤢"
	local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0,4); bc.Parent = badge
	badge.Parent = img
	img.MouseButton1Click:Connect(function() openMaximize(img) end)
	img.Parent = activeBuildParent
	return img
end

local KEY_MASK = "••••••••••••••••"
local function wireMaskedKey(box, getter)
	box.Text = getter() ~= "" and KEY_MASK or ""
	box.Focused:Connect(function() if box.Text == KEY_MASK then box.Text = "" end end)
	box.FocusLost:Connect(function() if box.Text == "" and getter() ~= "" then box.Text = KEY_MASK end end)
end

-- ============================================================
-- Settings tab
-- ============================================================
activeBuildParent = tabFrames.Settings
header("fal API key")
muted("Stored locally via plugin:SetSetting (plaintext on disk). BYO key only.")
local keyBox = textBox("Paste your fal API key…", 28, false)
wireMaskedKey(keyBox, getKey)
local saveKeyBtn = button("Save fal key", Color3.fromRGB(60, 130, 90))
divider()
header("Quality")
muted("Global tier for fal generation. Fast = z-image turbo (images) + LTX-2.3 (video) - quick & cheaper. Quality = nano-banana 2 (images) + Seedance 2.0 (video) - higher fidelity. Applies to image generate/edit and video. (3D & material models are fixed.)")
local qualityMode = "quality"
local qualityBtn = button("✦ Quality")
local fastBtn = button("⚡ Fast")
local function refreshQualityButtons()
	fastBtn.BackgroundColor3 = qualityMode == "fast" and COL_ON or COL_OFF
	qualityBtn.BackgroundColor3 = qualityMode == "quality" and COL_ACCENT or COL_OFF
end

-- ---- selector state + per-tier option lists (Fast = z-image/LTX-2.3, Quality = nano-banana/Seedance 2.0) ----
local IMAGE_SIZE_MAP = { -- z-image (Fast) image_size presets; nano-banana (Quality) takes the aspect verbatim
	["1:1"] = "square_hd", ["16:9"] = "landscape_16_9", ["9:16"] = "portrait_16_9",
	["4:3"] = "landscape_4_3", ["3:4"] = "portrait_4_3",
}
local imageAspect, imageResolution = "1:1", "1K"
local videoDuration, videoRes, videoAspect, videoAudio, videoFace = "6", "1080p", "16:9", true, "Auto"
local applyTarget, terrainBaseMat, studsPerTile, lastMV = "Selected part", "Grass", 4, nil

local function imageAspectOptions()
	if qualityMode == "quality" then return { "1:1", "16:9", "9:16", "4:3", "3:4", "3:2", "2:3", "21:9", "auto" } end
	return { "1:1", "16:9", "9:16", "4:3", "3:4" } -- must stay within IMAGE_SIZE_MAP keys for z-image
end
local function imageResOptions()
	if qualityMode == "quality" then return { "1K", "2K", "4K", "0.5K" } end
	return { "preset" } -- z-image has no resolution knob (the size preset is the resolution)
end
local function videoDurationOptions()
	if qualityMode == "quality" then return { "5", "4", "6", "7", "8", "9", "10", "11", "12", "13", "14", "15", "auto" } end
	return { "6", "8", "10", "12", "14", "16", "18", "20" }
end
local function videoResOptions()
	if qualityMode == "quality" then return { "720p", "480p", "1080p", "4k" } end
	return { "1080p", "1440p", "2160p" } -- LTX has no 720p; Roblox downscales to its 720p cap on playback
end
local function videoAspectOptions()
	if qualityMode == "quality" then return { "16:9", "9:16", "21:9", "4:3", "1:1", "3:4", "auto" } end
	return { "16:9", "9:16" }
end

-- ============================================================
-- Image tab (shared workspace → "current image")
-- ============================================================
activeBuildParent = tabFrames.Image
header("Image")
muted("Generate or edit an image, or load one from disk. The current image feeds the 3D, Material, and Video tabs - match the aspect to your video to avoid distortion.")
local imgGenPromptBox = textBox("Generate - e.g. a fire-breathing dragon, concept art", 48, true)
local imgAspectDD = dropdown("Aspect", imageAspectOptions(), function(v) imageAspect = v end)
local imgResDD = dropdown("Resolution", imageResOptions(), function(v) imageResolution = v end)
local genImgBtn = button("Generate image", COL_ACCENT)
local imgEditPromptBox = textBox("Edit - e.g. make it icy blue, add glowing eyes", 48, true)
local editImgBtn = button("Edit current image", COL_ACCENT)
local resetImgBtn = button("Reset to original", Color3.fromRGB(80, 80, 90))
local pickBtn = button("Load image from disk…", Color3.fromRGB(80, 80, 90))
local pickedLabel = muted("(no image yet)", 18)
local previewImage = imagePreview(200)

-- ============================================================
-- 3D tab
-- ============================================================
activeBuildParent = tabFrames["3D"]
header("Text → 3D")
local promptBox = textBox("e.g. a wooden treasure chest with iron bands", 64, true)
local genTextBtn = button("Generate from text")
divider()
header("Image → 3D")
muted("Uses the current image from the Image tab:")
local thumb3D = imagePreview(200)
local genImageBtn = button("Generate 3D from current image")
local urlBox = textBox("(GLB URL appears here - copy + use Studio's 3D Importer)", 28, false)
urlBox.TextEditable = false
urlBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 120)

-- ============================================================
-- Material tab (PATINA)
-- ============================================================
activeBuildParent = tabFrames.Material
header("Material (PATINA)")
muted("Make a seamless tiling PBR material from a description or the current image, then apply it to a selected part or paint it across terrain.")
local matPromptBox = textBox("e.g. weathered cobblestone, seamless, top-down", 48, true)
local genMatBtn = button("Generate material from text", COL_ACCENT)
muted("…or use the current image (from the Image tab):")
local matSrcThumb = imagePreview(200)
local genMatFromImageBtn = button("Material from current image", COL_ACCENT)
muted("Generated material:")
local matPreview = imagePreview(160)
divider()
muted("Apply it. Terrain mode overrides a built-in material everywhere it's painted. Studs/tile sets the repeat scale - adjustable live after applying.", 48)
dropdown("Apply to", { "Selected part", "Terrain" }, function(v) applyTarget = v end)
dropdown("Terrain material", { "Grass", "LeafyGrass", "Ground", "Rock", "Sand", "Snow", "Mud", "Slate", "Basalt", "Sandstone", "Cobblestone", "Concrete" }, function(v) terrainBaseMat = v end)
dropdown("Studs / tile", { "4", "6", "8", "12", "16", "24", "32", "64", "128", "2", "1" }, function(v) studsPerTile = tonumber(v) or 4; if lastMV then lastMV.StudsPerTile = studsPerTile end end)
local applyMatBtn = button("Apply material", Color3.fromRGB(80, 80, 90))
local resetTerrainBtn = button("Reset terrain overrides", Color3.fromRGB(70, 70, 80))

-- ============================================================
-- Video tab
-- ============================================================
activeBuildParent = tabFrames.Video
header("Video")
muted("Generate a clip with fal, then play it on a part's surface as a screen. Fast = LTX-2.3, Quality = Seedance 2.0 (toggle in Settings).")
local vidDurDD = dropdown("Duration (s)", videoDurationOptions(), function(v) videoDuration = v end)
local vidResDD = dropdown("Resolution", videoResOptions(), function(v) videoRes = v end)
local vidAspectDD = dropdown("Aspect", videoAspectOptions(), function(v) videoAspect = v end)
dropdown("Audio", { "On", "Off" }, function(v) videoAudio = (v == "On") end)
divider()
header("Text → video")
local vidPromptBox = textBox("e.g. neon city skyline at night, slow flythrough", 48, true)
local genVidTextBtn = button("Generate from text", COL_ACCENT)
divider()
header("Image → video")
muted("Animates the current image (Image tab) - describe the motion:")
local videoSrcThumb = imagePreview(200)
local vidMotionBox = textBox("e.g. gentle camera push-in, flickering torchlight", 48, true)
local genVidImageBtn = button("Generate from current image", COL_ACCENT)
divider()
header("Add to scene")
muted("Roblox can't upload video from a plugin. Open the link, download the .mp4, import it via File ▸ Import (the Universal Importer beta), then paste the asset ID and select a part.")
local vidUrlBox = textBox("(.mp4 link appears here after generating)", 28, false)
vidUrlBox.TextEditable = false
vidUrlBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 120)
local vidAssetBox = textBox("Paste video asset ID (rbxassetid:// or number)…", 28, false)
dropdown("Face", { "Auto", "Front", "Back", "Top", "Bottom", "Right", "Left" }, function(v) videoFace = v end)
local addVidBtn = button("Play on selected part", Color3.fromRGB(80, 80, 90))

refreshQualityButtons()
showTab("Settings")

-- ============================================================
-- Shared image state + preview
-- ============================================================
local activeImageUrl, baselineImageUrl = nil, nil

local function showPreview(target, url)
	local ok, err = pcall(function()
		local ei = urlToEditableImage(url)
		local shown = pcall(function() target.ImageContent = Content.fromObject(ei) end)
		if not shown then shown = pcall(function() target.Image = Content.fromObject(ei) end) end
		if not shown then error("couldn't assign EditableImage to the ImageLabel") end
	end)
	if not ok then appendStatus("(preview unavailable: " .. tostring(err) .. ")") end
end

local currentImageDisplays = { previewImage, thumb3D, matSrcThumb, videoSrcThumb }
local function setActiveImage(url, isBaseline)
	activeImageUrl = url
	if isBaseline then baselineImageUrl = url end
	pickedLabel.Text = "✓ current image set"
	pickedLabel.TextColor3 = Color3.fromRGB(120, 220, 120)
	local ok, err = pcall(function()
		local ei = urlToEditableImage(url)
		local c = Content.fromObject(ei)
		for _, lbl in ipairs(currentImageDisplays) do
			assignImage(lbl, c)
		end
	end)
	if not ok then appendStatus("(preview unavailable: " .. tostring(err) .. ")") end
end

-- ============================================================
-- fal image gen/edit - routed by qualityMode
-- ============================================================
local function imageUrlFromResult(result)
	return result.images and result.images[1] and result.images[1].url
end
local function generateImageUrl(prompt)
	if qualityMode == "quality" then
		return imageUrlFromResult(falRunJob(IMAGE_GEN_MODEL_QUALITY, { prompt = prompt, aspect_ratio = imageAspect, resolution = imageResolution, output_format = "png" }, appendStatus))
	end
	return imageUrlFromResult(falRunJob(IMAGE_GEN_MODEL_FAST, { prompt = prompt, image_size = IMAGE_SIZE_MAP[imageAspect] or "square_hd", output_format = "png" }, appendStatus))
end
local function editImageUrl(prompt, imageUrl)
	if qualityMode == "quality" then
		return imageUrlFromResult(falRunJob(IMAGE_EDIT_MODEL_QUALITY, { prompt = prompt, image_urls = { imageUrl }, output_format = "png" }, appendStatus))
	end
	return imageUrlFromResult(falRunJob(IMAGE_EDIT_MODEL_FAST, { prompt = prompt, image_url = imageUrl, output_format = "png" }, appendStatus))
end

-- ============================================================
-- Busy state
-- ============================================================
local jobButtons = { genTextBtn, genImageBtn, genImgBtn, editImgBtn, genMatBtn, genMatFromImageBtn, applyMatBtn, genVidTextBtn, genVidImageBtn }
local function setBusy(busy)
	for _, b in ipairs(jobButtons) do
		b.AutoButtonColor = not busy
		b.Active = not busy
		b.TextTransparency = busy and 0.4 or 0
	end
end

local function requireKey()
	if getKey() == "" then setStatus("Save your fal API key first (Settings tab)."); return false end
	return true
end

-- ============================================================
-- Wire-up: Settings
-- ============================================================
-- repopulate the tier-dependent dropdowns when Fast/Quality flips (clamps now-invalid values)
local function refreshTierDropdowns()
	imgAspectDD.rebuild(imageAspectOptions())
	imgResDD.rebuild(imageResOptions())
	vidDurDD.rebuild(videoDurationOptions())
	vidResDD.rebuild(videoResOptions())
	vidAspectDD.rebuild(videoAspectOptions())
end

saveKeyBtn.MouseButton1Click:Connect(function()
	local typed = keyBox.Text
	if typed == "" or typed == KEY_MASK then
		setStatus(getKey() ~= "" and "Key unchanged." or "Paste a key first."); return
	end
	setKey(typed); keyBox.Text = KEY_MASK; setStatus("fal key saved.")
end)
fastBtn.MouseButton1Click:Connect(function() qualityMode = "fast"; refreshQualityButtons(); refreshTierDropdowns(); setStatus("Quality: Fast (z-image turbo · LTX-2.3 video).") end)
qualityBtn.MouseButton1Click:Connect(function() qualityMode = "quality"; refreshQualityButtons(); refreshTierDropdowns(); setStatus("Quality: Quality (nano-banana 2 · Seedance 2.0 video).") end)

-- ============================================================
-- Wire-up: Image tab
-- ============================================================
genImgBtn.MouseButton1Click:Connect(function()
	local p = imgGenPromptBox.Text
	if p == "" or p == nil then setStatus("Enter an image prompt first."); return end
	if not requireKey() then return end
	task.spawn(function()
		setBusy(true)
		setStatus(string.format("Generating image (%s)…", qualityMode))
		local ok, urlOrErr = pcall(generateImageUrl, p)
		if ok and urlOrErr then
			appendStatus("✓ Image generated - previewing…"); setActiveImage(urlOrErr, true)
		else
			appendStatus("Image gen failed: " .. tostring(urlOrErr))
		end
		setBusy(false)
	end)
end)

editImgBtn.MouseButton1Click:Connect(function()
	if not activeImageUrl then setStatus("Generate or load an image first."); return end
	local p = imgEditPromptBox.Text
	if p == "" or p == nil then setStatus("Enter an edit instruction first."); return end
	if not requireKey() then return end
	task.spawn(function()
		setBusy(true)
		setStatus(string.format("Editing image (%s)…", qualityMode))
		local ok, urlOrErr = pcall(editImageUrl, p, activeImageUrl)
		if ok and urlOrErr then
			appendStatus("✓ Edited - previewing…"); setActiveImage(urlOrErr, false)
		else
			appendStatus("Edit failed: " .. tostring(urlOrErr))
		end
		setBusy(false)
	end)
end)

resetImgBtn.MouseButton1Click:Connect(function()
	if not baselineImageUrl then setStatus("Nothing to reset to."); return end
	setActiveImage(baselineImageUrl, false); setStatus("Reset to the original image.")
end)

pickBtn.MouseButton1Click:Connect(function()
	if not requireKey() then return end
	local file = StudioService:PromptImportFile({ "png", "jpg", "jpeg", "webp" })
	if not file then setStatus("No file picked."); return end
	local ok, bytes = pcall(function() return file:GetBinaryContents() end)
	if not ok then setStatus("Couldn't read file: " .. tostring(bytes)); return end
	if #bytes > MAX_IMAGE_BYTES then
		setStatus(string.format("Image is %.1f MB - pick something under %d MB.", #bytes / 1024 / 1024, MAX_IMAGE_BYTES / 1024 / 1024)); return
	end
	local lower = string.lower(file.Name)
	local mime = "image/png"
	if string.match(lower, "%.jpe?g$") then mime = "image/jpeg" elseif string.match(lower, "%.webp$") then mime = "image/webp" end
	pickedLabel.Text = string.format("uploading %s…", file.Name); pickedLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	task.spawn(function()
		local upOk, urlOrErr = pcall(falStorageUpload, bytes, file.Name, mime)
		if not upOk then
			pickedLabel.Text = "upload failed: " .. tostring(urlOrErr); pickedLabel.TextColor3 = Color3.fromRGB(220, 100, 100)
			setStatus("Image upload failed. " .. tostring(urlOrErr)); return
		end
		setStatus("Image loaded - see preview."); setActiveImage(urlOrErr, true)
	end)
end)

-- ============================================================
-- Wire-up: 3D tab
-- ============================================================
local function runMeshJob(model, payload, label)
	setBusy(true); setStatus(string.format("Submitting %s…", label))
	local ok, result = pcall(falRunJob, model, payload, appendStatus)
	if not ok then appendStatus("Error: " .. tostring(result)); setBusy(false); return end
	appendStatus("Job complete.")
	local glbUrl = extractGlbUrl(result)
	if not glbUrl then appendStatus("No GLB URL: " .. HttpService:JSONEncode(result)); setBusy(false); return end
	urlBox.Text = glbUrl
	appendStatus("GLB ready - copy the URL (3D tab) and drag the .glb onto the viewport via Studio's 3D Importer.")
	setBusy(false)
end

genTextBtn.MouseButton1Click:Connect(function()
	local p = promptBox.Text
	if p == "" or p == nil then setStatus("Enter a prompt first."); return end
	if not requireKey() then return end
	task.spawn(runMeshJob, TEXT_MODEL, { prompt = p, face_limit = DEFAULT_FACE_LIMIT, texture = true }, "text-to-3D")
end)

genImageBtn.MouseButton1Click:Connect(function()
	if not activeImageUrl then setStatus("No current image - make one in the Image tab first."); return end
	if not requireKey() then return end
	task.spawn(runMeshJob, IMAGE_MODEL, { image_url = activeImageUrl, face_limit = DEFAULT_FACE_LIMIT, texture = true }, "image-to-3D")
end)

-- ============================================================
-- Wire-up: Material tab (PATINA)
-- ============================================================
local MaterialService = game:GetService("MaterialService")
local Selection = game:GetService("Selection")
local matMaps = nil
local matVariantCount = 0
local terrainOverrides = {} -- Enum.Material -> true, for Reset

local function buildMaterialFromResult(result)
	local urls = {}
	for _, img in ipairs(result.images or {}) do
		if img.map_type then urls[img.map_type] = img.url end
	end
	if not urls.basecolor then error("no basecolor in response: " .. HttpService:JSONEncode(result)) end
	appendStatus("Decoding maps…")
	local m = {}
	m.ColorMap = urlToEditableImage(urls.basecolor)
	if urls.normal then m.NormalMap = urlToEditableImage(urls.normal) end
	if urls.roughness then m.RoughnessMap = urlToEditableImage(urls.roughness) end
	if urls.metalness then m.MetalnessMap = urlToEditableImage(urls.metalness) end
	matMaps = m
	assignImage(matPreview, Content.fromObject(m.ColorMap))
end

local function runMaterialJob(model, payload, label)
	setBusy(true); setStatus(label)
	local ok, result = pcall(falRunJob, model, payload, appendStatus)
	if not ok then appendStatus("Material gen failed: " .. tostring(result)); setBusy(false); return end
	local okB, errB = pcall(buildMaterialFromResult, result)
	if okB then appendStatus("✓ Material ready - select a part and Apply.") else appendStatus("Material failed: " .. tostring(errB)) end
	setBusy(false)
end

genMatBtn.MouseButton1Click:Connect(function()
	local p = matPromptBox.Text
	if p == "" or p == nil then setStatus("Enter a material prompt first."); return end
	if not requireKey() then return end
	task.spawn(runMaterialJob, PATINA_MATERIAL_MODEL, { prompt = p, output_format = "png", maps = { "basecolor", "normal", "roughness", "metalness" } }, "Generating material from text (PATINA)…")
end)

genMatFromImageBtn.MouseButton1Click:Connect(function()
	if not activeImageUrl then setStatus("No current image - make one in the Image tab first."); return end
	if not requireKey() then return end
	task.spawn(runMaterialJob, PATINA_FROM_IMAGE_MODEL, { image_url = activeImageUrl, output_format = "png", maps = { "basecolor", "normal", "roughness", "metalness" } }, "Making material from current image (PATINA)…")
end)

local function uploadImageAsset(ei, name)
	local res, assetId = AssetService:CreateAssetAsync(ei, Enum.AssetType.Image, { Name = name })
	if not assetId then error("'" .. name .. "' upload failed: " .. tostring(res)) end
	return "rbxassetid://" .. tostring(assetId)
end

applyMatBtn.MouseButton1Click:Connect(function()
	if not matMaps then setStatus("Generate a material first."); return end
	local toTerrain = (applyTarget == "Terrain")
	local part = nil
	if not toTerrain then
		part = Selection:Get()[1]
		if not (part and part:IsA("BasePart")) then setStatus("Select a Part, or switch 'Apply to' → Terrain."); return end
	end
	task.spawn(function()
		setBusy(true); setStatus("Uploading maps to Roblox (MaterialVariant needs asset IDs)…")
		local ok, errOrUris = pcall(function()
			local uris = {}
			appendStatus("  uploading basecolor…"); uris.color = uploadImageAsset(matMaps.ColorMap, "falPatina_basecolor")
			if matMaps.NormalMap then appendStatus("  uploading normal…"); uris.normal = uploadImageAsset(matMaps.NormalMap, "falPatina_normal") end
			if matMaps.RoughnessMap then appendStatus("  uploading roughness…"); uris.rough = uploadImageAsset(matMaps.RoughnessMap, "falPatina_roughness") end
			if matMaps.MetalnessMap then appendStatus("  uploading metalness…"); uris.metal = uploadImageAsset(matMaps.MetalnessMap, "falPatina_metalness") end
			return uris
		end)
		if not ok then
			appendStatus("Upload failed: " .. tostring(errOrUris))
			appendStatus("(Enable Studio Beta: 'CreateAssetAsync Lua API', then restart.)")
			setBusy(false); return
		end
		local uris = errOrUris
		local baseMat = toTerrain and (Enum.Material[terrainBaseMat] or Enum.Material.Grass) or Enum.Material.SmoothPlastic
		matVariantCount += 1
		local mv = Instance.new("MaterialVariant")
		mv.Name = "falPatina_" .. matVariantCount
		mv.BaseMaterial = baseMat
		mv.StudsPerTile = studsPerTile
		mv.ColorMap = uris.color
		if uris.normal then mv.NormalMap = uris.normal end
		if uris.rough then mv.RoughnessMap = uris.rough end
		if uris.metal then mv.MetalnessMap = uris.metal end
		mv.Parent = MaterialService
		lastMV = mv
		if toTerrain then
			MaterialService:SetBaseMaterialOverride(baseMat, mv.Name)
			terrainOverrides[baseMat] = true
			appendStatus("✓ Terrain '" .. terrainBaseMat .. "' re-skinned (StudsPerTile " .. studsPerTile .. "). Tune Studs/tile live; if nothing changes, paint some terrain with " .. terrainBaseMat .. " first.")
		else
			part.Material = baseMat
			part.MaterialVariant = mv.Name
			appendStatus("✓ Applied to " .. part.Name .. " (StudsPerTile " .. studsPerTile .. "). Tune Studs/tile live.")
		end
		setBusy(false)
	end)
end)

resetTerrainBtn.MouseButton1Click:Connect(function()
	local n = 0
	for mat in pairs(terrainOverrides) do
		pcall(function() MaterialService:SetBaseMaterialOverride(mat, "") end)
		terrainOverrides[mat] = nil; n += 1
	end
	setStatus(n > 0 and ("Cleared " .. n .. " terrain override(s).") or "No terrain overrides to clear.")
end)

-- ============================================================
-- Wire-up: Video tab
-- ============================================================
local ChangeHistoryService = game:GetService("ChangeHistoryService")

-- pick the part's biggest face so a flat panel gets the screen on its large surface
local function largestFace(part)
	local s = part.Size
	local opts = { { Enum.NormalId.Front, s.X * s.Y }, { Enum.NormalId.Top, s.X * s.Z }, { Enum.NormalId.Right, s.Z * s.Y } }
	local best, bestArea = Enum.NormalId.Front, -1
	for _, o in ipairs(opts) do
		if o[2] > bestArea then best, bestArea = o[1], o[2] end
	end
	return best
end

-- LTX (Fast) requires 1080p when duration >10s (with fps=25, which is the default we send).
local function effectiveVideoRes()
	if qualityMode ~= "quality" then
		local d = tonumber(videoDuration)
		if d and d > 10 and videoRes ~= "1080p" then return "1080p" end
	end
	return videoRes
end
local function videoUrlFromResult(result)
	return result and result.video and result.video.url
end

local function runVideoJob(model, payload, label)
	setBusy(true); setStatus(label)
	local ok, result = pcall(falRunJob, model, payload, appendStatus)
	if not ok then appendStatus("Video gen failed: " .. tostring(result)); setBusy(false); return end
	local url = videoUrlFromResult(result)
	if not url then appendStatus("No video URL: " .. HttpService:JSONEncode(result)); setBusy(false); return end
	vidUrlBox.TextEditable = true -- allow select/copy of the link
	vidUrlBox.Text = url
	appendStatus("✓ Video ready. Open the link → download the .mp4 → File ▸ Import → paste the asset ID below.")
	setStatus("Video ready - copy the .mp4 link from the Video tab.")
	setBusy(false)
end

genVidTextBtn.MouseButton1Click:Connect(function()
	local p = vidPromptBox.Text
	if p == "" or p == nil then setStatus("Enter a video prompt first."); return end
	if not requireKey() then return end
	local model = qualityMode == "quality" and VIDEO_T2V_QUALITY or VIDEO_T2V_FAST
	local res = effectiveVideoRes()
	local payload = {
		prompt = p,
		duration = videoDuration,
		aspect_ratio = videoAspect,
		resolution = res,
		generate_audio = videoAudio,
	}
	task.spawn(runVideoJob, model, payload, string.format("Generating video (%s · %ss · %s · %s)…", qualityMode, videoDuration, res, videoAspect))
end)

genVidImageBtn.MouseButton1Click:Connect(function()
	if not activeImageUrl then setStatus("No current image - make one in the Image tab first."); return end
	local p = vidMotionBox.Text
	if p == "" or p == nil then setStatus("Describe the motion for image → video first."); return end
	if not requireKey() then return end
	local model = qualityMode == "quality" and VIDEO_I2V_QUALITY or VIDEO_I2V_FAST
	local res = effectiveVideoRes()
	local payload = {
		image_url = activeImageUrl,
		prompt = p,
		duration = videoDuration,
		aspect_ratio = videoAspect,
		resolution = res,
		generate_audio = videoAudio,
	}
	task.spawn(runVideoJob, model, payload, string.format("Generating video from image (%s · %ss · %s)…", qualityMode, videoDuration, res))
end)

local function normalizeVideoAsset(s)
	if not s then return nil end
	local digits = string.match(s, "%d+")
	if not digits then return nil end
	return "rbxassetid://" .. digits
end

addVidBtn.MouseButton1Click:Connect(function()
	local asset = normalizeVideoAsset(vidAssetBox.Text)
	if not asset then setStatus("Paste a valid video asset ID first (import the .mp4, then paste its id)."); return end
	local part = Selection:Get()[1]
	if not (part and part:IsA("BasePart")) then setStatus("Select a Part in the viewport, then Play."); return end
	local face = (videoFace == "Auto") and largestFace(part) or Enum.NormalId[videoFace]
	local recording = nil
	pcall(function() recording = ChangeHistoryService:TryBeginRecording("falgen: video on part") end)
	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "falVideoScreen"
	surfaceGui.Face = face
	surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surfaceGui.PixelsPerStud = 50
	surfaceGui.LightInfluence = 0 -- fullbright so the video isn't darkened by lighting
	surfaceGui.Adornee = part
	surfaceGui.Parent = part
	local vf = Instance.new("VideoFrame")
	vf.Name = "Video"
	vf.Size = UDim2.new(1, 0, 1, 0)
	vf.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	vf.Looped = true
	vf.Volume = videoAudio and 5 or 0
	vf.Parent = surfaceGui
	vf.Video = asset -- set AFTER parenting (staff-confirmed ordering, else it can stick unplayed)
	vf:Play()
	pcall(function() vf:SetStudioPreview(true) end) -- show it at edit time, no Play needed
	if recording then
		pcall(function() ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit) end)
	end
	setStatus("✓ Video screen on " .. part.Name .. " (" .. face.Name .. " face). If blank: the upload may still be in moderation.")
end)

print("[falgen] loaded - tabs: Settings · Image · 3D · Material · Video.")
