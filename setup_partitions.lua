--run after flashing new firmware with "erase flash" option
lfs_size = 8192 * 8 --64kib
pt=node.getpartitiontable()
if pt.lfs_size == 0 then
	npt = {}
	npt.lfs_addr = pt.spiffs_addr
	npt.lfs_size = lfs_size
	npt.spiffs_addr = pt.spiffs_addr + lfs_size
	npt.spiffs_size = pt.spiffs_size - lfs_size
	node.setpartitiontable(npt)
end