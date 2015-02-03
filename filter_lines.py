#!/usr/local/bin/python
import sys

def main(argv):
	for file in argv[1:]:
		with open(file) as infile:
			lines = map(lambda x: x.rstrip(), list(infile))
			lines_filtered = map(lambda x: lines[x[0]], filter(lambda x: x[0] == 0 or x[1] != "" or lines[x[0]-1] != "", enumerate(lines)))
			if lines_filtered[-1] != "":
				lines_filtered.append("")
		with open(file, "w") as outfile:
			outfile.write("\n".join(lines_filtered))

if __name__ == "__main__":
	main(sys.argv)