local ttfs = require("ttfs")

ttfs:create_empty_image()

print(string.format("%04X", ttfs:get_first_free_block()))
--print("Writing image to file")
--ttfs:write_image("test.bin")