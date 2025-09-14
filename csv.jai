CsvData :: struct {
	rows : [][]string;
}

csv_parse :: (source: string) -> CsvData {
	region_timer("parse csv");

	csv : CsvData;
	ptr : int;

	buffer : [..]u8;
	array_reserve(*buffer, 1024); defer array_free(buffer);
	current_append :: (c : u8) #expand {
		array_add(*buffer, c);
	}
	current_reset :: () #expand {
		buffer.count = 0;
	}
	current_to_string :: () -> string #expand {
		return cast(string)buffer;
	}
	current_copy :: () -> string #expand {
		return copy_string(cast(string)buffer);
	}

	SUBMIT :: () #expand {
		array_add(*row, current_copy());
		current_reset();
	}

	open : bool;
	rows : [..][]string;
	array_reserve(*rows, 1024 * 10);
	row : [..]string;
	while ptr < source.count {
		if source[ptr] == "," {
			if open {
				current_append(",");
			} else {
				SUBMIT();
			}
		} else if source[ptr] == "\"" {
			if !open {
				open = true;
			} else {
				if ptr+1<source.count && source[ptr+1] == "\"" {
					current_append("\"");
					ptr += 1;
				} else {
					open = false;
				}
			}
		} else if source[ptr] == "\n" {
			if buffer.count > 0 {
				SUBMIT();
			}
			array_add(*rows, row);
			row.data      = null;
			row.allocated = 0;
			row.count     = 0;
		} else {
			current_append(source[ptr]);
		}
		ptr += 1;
	}
	csv.rows = rows;
	return csv;
}

csv_free :: (csv: *CsvData) {
	for row:csv.rows {
		for item:row {
			free(item);
		}
		array_free(row);
	}
}

#import "Basic";
#import "String";
#import "Text_File_Handler";
