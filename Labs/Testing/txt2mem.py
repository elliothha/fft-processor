path = "C:/Users/Elliot/Desktop/Processor/Labs/Testing/"

with open(path + "colors.txt", 'r') as txtFile:
    lines = txtFile.readlines()

with open(path + "colors.mem", 'w') as memFile:
    last_idx = len(lines) - 1
    
    for idx, line in enumerate(lines):
        channel_vals = line.strip()[4:-1].split(',')
        binary_vals = [format(int(val), '08b') for val in channel_vals]
        color = ''.join(binary_vals)

        if idx == last_idx:
            memFile.write(color)
        else:
            memFile.write(color + '\n')