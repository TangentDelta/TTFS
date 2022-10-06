local ttfs = require("ttfs")

ttfs:create_empty_image()

for i = 1, 40 do
    ttfs:create_file(0x11, string.format("TEST%d.TXT", i))
end


ttfs:list_files(0x11)

--print(string.format("%04X", ttfs:get_first_free_block()))
print("Writing image to file")
ttfs:write_image("test.bin")