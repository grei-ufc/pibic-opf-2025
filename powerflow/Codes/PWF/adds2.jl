import Pkg

print("\033c")

# 1. Clean up
try Pkg.rm("PWF") catch end
try Pkg.rm("Ipopt") catch end
try Pkg.rm("PowerModels") catch end

# 2. Install the Golden Combination
# Ipopt v0.9 + PowerModels v0.19 + JuMP v0.21
# This combination works on Julia 1.8+
Pkg.add(Pkg.PackageSpec(name="Ipopt", version="0.9"))
Pkg.add(Pkg.PackageSpec(name="PowerModels", version="0.19"))
Pkg.add(Pkg.PackageSpec(name="JuMP", version="0.21.1"))

# 3. Add your local package (which now allows PM v0.19)
Pkg.develop("PWF")

# 4. Final verification
Pkg.build("Ipopt")
Pkg.status()