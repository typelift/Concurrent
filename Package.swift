import PackageDescription

let package = Package(
	name: "Concurrent",
	targets: [
		Target(
			name: "Concurrent",
			dependencies: []),
  ]
)

let libConcurrent = Product(name: "Concurrent", type: .Library(.Dynamic), modules: "Concurrent")
products.append(libConcurrent)
