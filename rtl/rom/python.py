import math

def generate_mif(filename, data_type="cos", depth=512, width=16):
    """
    data_type: "cos" 或 "sin"
    depth: 512 (对应 angle[15:7])
    width: 16 (Q1.15 格式)
    """
    with open(filename, 'w') as f:
        # MIF 文件头设置
        f.write(f"DEPTH = {depth};\n")
        f.write(f"WIDTH = {width};\n")
        f.write("ADDRESS_RADIX = DEC;\n")
        f.write("DATA_RADIX = HEX;\n")
        f.write("CONTENT BEGIN\n")

        for i in range(depth):
            # 将索引映射回 0~360度
            # angle 是 16位全圆（65536），索引 i 是高9位，所以对应 angle = i << 7
            theta = 2 * math.pi * (i << 7) / 65536
            
            if data_type == "cos":
                val = math.cos(theta)
            else:
                val = math.sin(theta)
            
            # 转换为 Q1.15 定点数
            # 32768 对应 1.0，处理有符号数补码
            q_val = int(round(val * 32767))
            
            # 处理负数的 16位补码十六进制表示
            if q_val < 0:
                hex_val = hex((1 << width) + q_val)[2:].upper().zfill(4)
            else:
                hex_val = hex(q_val)[2:].upper().zfill(4)
            
            f.write(f"    {i} : {hex_val};\n")
        
        f.write("END;\n")

# 执行生成
generate_mif("cos_lut.mif", "cos")
generate_mif("sin_lut.mif", "sin")
print("MIF files generated successfully!")