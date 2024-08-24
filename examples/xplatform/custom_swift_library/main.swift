import Custom
import Regular

let regular = Regular()
let custom = Custom(regular: regular)

print(String(describing: custom))