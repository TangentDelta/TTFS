local ttfs = {}

local rootdir = 0x11

function ttfs:read_image(image_path)
    local F = io.open(image_path, "rb")
    if F then
        local file_contents = F:read("a")
        for i = 1, file_contents:len() do
            self.contents[i - 1] = string.byte(string.sub(file_contents, i, i))
        end

        F:close()
    end
end

function ttfs:write_image(image_path)
    local F = io.open(image_path, "wb")
    if F then
        for i = 0, 512 * (2^16) do
            F:write(string.char(self.contents[i]))
        end
    end
end

function ttfs:block_read(lba)
    --print(string.format("Reading block $%04X", lba))
    local block = {}
    for i = 0, 511 do
        block[i] = self.contents[(lba * 512) + i]
    end

    return block
end

function ttfs:block_write(lba, block)
    --print(string.format("Writing block $%04X", lba))
    for i = 0, 511 do
        self.contents[(lba * 512) + i] = block[i]
    end
end

function ttfs:get_block_free(lba)
    local bit_address = lba & 0x7
    local byte_address = (lba >> 3) & 0x1FF
    local bitmap_block = (lba >> 12) + 1
    
    local block = self:block_read(bitmap_block)
    local mapbyte = block[byte_address]
    local mapbit = (mapbyte >> bit_address) & 1

    return mapbit ~= 0
end

function ttfs:get_first_free_block()
    for i = 1, 8 do
        for j = 0,511 do
            local mapbyte = self.contents[(i*512) + j]
            if mapbyte ~= 0xff then
                for k = 0, 7 do
                    local testbit = (mapbyte >> k) & 1
                    if testbit == 0 then
                        return ((i-1) << 12) + (j << 3) + k
                    end
                end
            end
        end
    end
end

function ttfs:set_block_free(lba, isfree)
    local bit_address = lba & 0x7
    local byte_address = (lba >> 3) & 0x1FF
    local bitmap_block = (lba >> 12) + 1
    
    local block = self:block_read(bitmap_block)
    local mapbyte = block[byte_address]
    if isfree then
        block[byte_address] = mapbyte & ~(1 << bit_address)
    else
        block[byte_address] = mapbyte | (1 << bit_address)
    end

    self:block_write(bitmap_block, block)
end

function ttfs:list_files(dirlba)
    local block = self:block_read(dirlba)
    for i = 1, 31 do
        local entryaddr = i * 16

        -- If the first character is 00 (last entry in directory), stop reading directory entries
        if block[entryaddr] == 0 then
            return
        end

        local filename = ""
        for i = 0, 7 do
            filename = filename .. string.char(block[entryaddr + i])
        end

        local extension = ""
        for i = 8, 10 do
            extension = extension .. string.char(block[entryaddr + i])
        end

        print(string.format("%s.%s", filename, extension))
    end

    -- Continue listing files for the next chunk of the directory
    local nextlba = block[0] + (block[1] * 256)
    if nextlba ~= 0x0000 then
        self:list_files(nextlba)
    end
end

function ttfs:create_file(dirlba, filename)
    local block = self:block_read(dirlba)
    for i = 1, 31 do
        local entryaddr = i * 16

        if block[entryaddr] == 0 then
            local name, extension = string.match(filename, "([^.]*).(.*)")

            -- Make sure the name is 8 characters
            if string.len(name) < 8 then
                name = string.format("%8s", name)
            elseif string.len(name) > 8 then
                name = string.sub(name, 1, 8)
            end

            -- Extension is 3 characters
            if string.len(extension) < 3 then
                extension = string.format("%3s", extension)
            elseif string.len(extension) > 3 then
                extension = string.sub(extension, 1, 3)
            end

            -- Write out the file name to the entry
            for j = 1, 8 do
                block[entryaddr + (j-1)] = string.byte(string.sub(name, j, j))
            end

            -- Write out the file extension
            for j = 1, 3 do
                block[entryaddr + (j-1) + 8] = string.byte(string.sub(extension, j, j))
            end

            -- Get the first free block and assign it to this file
            local freeblock = self:get_first_free_block()
            self:set_block_free(freeblock, false)
            block[entryaddr + 0xB] = freeblock & 0xff
            block[entryaddr + 0xC] = freeblock >> 8

            -- Write the block back to storage
            self:block_write(dirlba, block)

            return
        end
    end

    local nextlba = block[0] + (block[1] * 256)

    -- If we don't have an extension to this directory, create one
    if nextlba == 0x0000 then
        -- Get the next free block and claim it
        nextlba = self:get_first_free_block()
        self:set_block_free(nextlba, false)

        -- Write this new block to this directory's link
        block[0] = nextlba & 0xFF
        block[1] = nextlba >> 8
        self:block_write(dirlba, block)
    end

    self:create_file(nextlba, filename)
end

function ttfs:init()
    print("TTFS library initialized.")
    self.contents = {}
end

function ttfs:create_empty_image()
    print("Creating a blank TTFS image...")
    for i = 0, 512 * (2^16) do
        self.contents[i] = 0
    end

    -- Reserve block 0
    self:set_block_free(0, false)

    -- Reserve the block usage bitmap
    for i = 1, 16 do
        self:set_block_free(i, false)
    end

    -- Reserve the root directory
    self:set_block_free(17, false)
end

ttfs:init()
return ttfs