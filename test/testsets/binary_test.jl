@testitem "png_image_metadata" tags = [:unit] begin
    import QuartoNotebookRunner as QNR

    # Create a minimal valid PNG with IHDR chunk
    function make_png(width, height)
        buf = IOBuffer()
        # PNG signature
        write(buf, UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
        # IHDR chunk
        ihdr_data = IOBuffer()
        write(ihdr_data, hton(UInt32(width)))
        write(ihdr_data, hton(UInt32(height)))
        write(ihdr_data, UInt8(8))  # bit depth
        write(ihdr_data, UInt8(2))  # color type (RGB)
        write(ihdr_data, UInt8(0))  # compression
        write(ihdr_data, UInt8(0))  # filter
        write(ihdr_data, UInt8(0))  # interlace
        ihdr = take!(ihdr_data)
        write(buf, hton(UInt32(length(ihdr))))  # length
        write(buf, b"IHDR")  # type
        write(buf, ihdr)     # data
        write(buf, hton(UInt32(0)))  # CRC (fake)
        # IDAT chunk (empty, just for structure)
        write(buf, hton(UInt32(0)))
        write(buf, b"IDAT")
        write(buf, hton(UInt32(0)))
        # IEND chunk
        write(buf, hton(UInt32(0)))
        write(buf, b"IEND")
        write(buf, hton(UInt32(0)))
        return take!(buf)
    end

    # Basic dimensions
    png = make_png(800, 600)
    meta = QNR.png_image_metadata(png; phys_correction = false)
    @test meta.width == 800
    @test meta.height == 600

    # Non-PNG throws
    @test_throws ArgumentError QNR.png_image_metadata(UInt8[1, 2, 3, 4, 5, 6, 7, 8])
end

@testitem "png_image_metadata with pHYs" tags = [:unit] begin
    import QuartoNotebookRunner as QNR

    # Create PNG with pHYs chunk for DPI testing
    function make_png_with_phys(width, height, x_ppm, y_ppm)
        buf = IOBuffer()
        # PNG signature
        write(buf, UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
        # IHDR chunk
        ihdr_data = IOBuffer()
        write(ihdr_data, hton(UInt32(width)))
        write(ihdr_data, hton(UInt32(height)))
        write(ihdr_data, UInt8(8))
        write(ihdr_data, UInt8(2))
        write(ihdr_data, UInt8(0))
        write(ihdr_data, UInt8(0))
        write(ihdr_data, UInt8(0))
        ihdr = take!(ihdr_data)
        write(buf, hton(UInt32(length(ihdr))))
        write(buf, b"IHDR")
        write(buf, ihdr)
        write(buf, hton(UInt32(0)))
        # pHYs chunk
        phys_data = IOBuffer()
        write(phys_data, hton(UInt32(x_ppm)))  # X pixels per unit
        write(phys_data, hton(UInt32(y_ppm)))  # Y pixels per unit
        write(phys_data, UInt8(1))             # unit is meter
        phys = take!(phys_data)
        write(buf, hton(UInt32(length(phys))))
        write(buf, b"pHYs")
        write(buf, phys)
        write(buf, hton(UInt32(0)))
        # IDAT
        write(buf, hton(UInt32(0)))
        write(buf, b"IDAT")
        write(buf, hton(UInt32(0)))
        # IEND
        write(buf, hton(UInt32(0)))
        write(buf, b"IEND")
        write(buf, hton(UInt32(0)))
        return take!(buf)
    end

    # 96 DPI = 3779.5275... pixels per meter
    dpi96_ppm = round(Int, 96 / 0.0254)
    png = make_png_with_phys(800, 600, dpi96_ppm, dpi96_ppm)

    # With correction, dimensions reflect CSS pixels at 96 DPI
    meta = QNR.png_image_metadata(png; phys_correction = true)
    @test meta.width == 800
    @test meta.height == 600

    # Higher DPI image should report smaller CSS dimensions
    dpi192_ppm = round(Int, 192 / 0.0254)
    png_hidpi = make_png_with_phys(800, 600, dpi192_ppm, dpi192_ppm)
    meta_hidpi = QNR.png_image_metadata(png_hidpi; phys_correction = true)
    @test meta_hidpi.width == 400
    @test meta_hidpi.height == 300
end
