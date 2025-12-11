import Pkg

# 1. Install the "Bridge" version of Ipopt FIRST
Pkg.add(Pkg.PackageSpec(name="Ipopt", version="0.9"))

# 2. Install compatible versions of core libraries
# (JuMP 0.21 will work with Ipopt 0.9)
Pkg.add(Pkg.PackageSpec(name="JuMP", version="0.21"))
Pkg.add(Pkg.PackageSpec(name="PowerModels", version="0.18"))
Pkg.add("Printf")
Pkg.add("PowerPlots")

# 3. Finally, add your local package
Pkg.add("PWF")

# 4. Build to confirm everything works
Pkg.build("Ipopt")

Pkg.status()