# This script should eventually become a ultimate copy of the all encompasing 
# textbook on multivariate time-series: Lütkepohl (2007). Some of the methods will be added
# from other papers, such as generalised VAR structure from Pesaran, Shin or computing 
# all reorderings in the standard identification structure.

#
###### Definition of the specialised type
# 

# The definition of the type rests on several specific neccessities
# There are things that are neccessary for proper definition of the VAR model and as
# such have to be included in the definition of the type. That is for example number
# of lags, the original data, the type.
# Other things can be foregone, but are often desirable to be stored, because they are
# computationally intensive and computing them only once is typically much better than
# recomputing them every time. However, in many applications, one might not even need them.
# 
# It is neccessary to balance the needs and strike the balance between initial speed of
# estimation and future speed. For example, I probably wouldn't like to have bootstrapped
# confidence intervals for some things, but I would surely keep the possibility to have them.
# 
# Moreover, the current estimation technique will probably be replaced by the method from 
# function restrictVAR2, because it is more general.

import Base: show

function estimateVAR(data::Matrix{Float64}, lags::Int, typ::AbstractString)
	X = dataMatrix(data, lags, typ)
	Y = data[(1+lags):end,:]
	obs, vars = size(data)
	C = (X'*X) \ X'*Y
	obs = obs - lags
	# Get numerical type
	typ=="None" && (ntyp = 0)
	typ=="Const" && (ntyp = 1)
	typ=="Const and trend" && (ntyp = 2)
	typ=="Trend" && (ntyp = 1)

	Σ = cov(Y-X*C)*(obs-1)/(obs-lags*vars-ntyp)

	return (X, Y, obs, vars, C, Σ, ntyp)
end

type varEstimate
	lags::Int
	typ::ASCIIString
	ntyp::Int
	vars::Int
	obs::Int
	X::Matrix{Float64}
	Y::Matrix{Float64}
	C::Matrix{Float64}
	Σ::Matrix{Float64}
	HPsi::Int
	HPhi::Int
	Phi::Array{Float64, 3}
	Psi::Array{Float64, 3}
	seriesNames::Vector{AbstractString}

	function varEstimate(data::Matrix{Float64},lags::Int, typ::AbstractString)
		(X, Y, obs, vars, C, Σ, ntyp) = estimateVAR(data::Matrix{Float64},lags::Int,typ::AbstractString)
		new(lags, typ, ntyp, vars, obs, X, Y, C, Σ, 0, 0, zeros(vars,vars,1), zeros(vars,vars,1), ["" for i=1:vars])
	end
end

# type varRestrictions
# 	R::Matrix{Float64}
# 	r::Vector{Float64}
# 	desc::Vector{ASCIIString}

# 	function varRestrictions(R::Matrix{Float64}, r::Vector{Float64}, desc::Vector{ASCIIString})
# 		@assume size(R)[1] == size(r)
# 		new(R, r, desc)
# 	end
# end

function Clag(est::varEstimate, lag)
	C = est.C
	ntyp = est.ntyp
	(coefs, vars) = size(C)
	lags = (coefs-ntyp)/vars
	lags < lag ? error("The demanded lag is higher than existing") : ""
	return C[1+ntyp+(((lag-1)*vars):((lag)*vars-1)),:]
end

function λ(est::varEstimate)
	# using Lutkepohl pg.139
	T = est.obs - est.lags
	K = est.vars
	β = vec(est.C)
	y = vec(est.Y)
	Z = est.X'
	Σ = est.Σ

	λv = -(K*T)/2 * log(2π) - T/2 * log(det(Σ)) - 1/2 * (y-kron(eye(K),Z')*β)'*(kron(inv(Σ), eye(T)))*(y-kron(eye(K),Z')*β)
	return λv[1]
end

function getR(a::Matrix{Bool})
	b = prod(size(a))
	c = sum(a)
	mat = fill(0.0, b, c)
	a = vec(a)
	d=1
	for i=1:b
		if a[i]
			mat[i,:] = [fill(0.0, d-1), 1, fill(0.0, c-d)]
			d += 1
		else
			mat[i,:] = fill(0.0, c)
		end
	end

	return mat
end



function restrictVAR(est::varEstimate, restrictions::Expr, egls::Bool=false)
	# TODO: Add small r from Lutkepohl 5.2
	# The original data are not changed, due to very different structure in the estimation (vectorisation)
	# The matrix R as the argument has to be of the size of the coefficients
	# Y stay the same

	# Naming conventions, this does not eat up memory, it is just renaming for more readability, 
	# it is parsed out
	Z = est.X'
	Y = est.Y
	Σ = est.Σ
	L = est.lags
	K = est.vars
	k = est.obs-est.lags
	R = restrictions.R
	r = restrictions.r

	z = vec(Y) - kron(eye(K), Z')*r

	if egls
		Σ1 = inv(Σ)
		γ = R'*kron(Σ1, Z*Z')*R \ R'*kron(Σ1, Z)*z
	else
		γ = (R'*kron(eye(K), Z*Z')*R) \ R'*kron(eye(K), Z)*z
	end
	β = R*γ + r
	est.C = reshape(β, L*K+1, K)

	est.Σ = (est.X*est.C-est.Y)'*(est.X*est.C-est.Y) / k
	return est
end

function restrictVAR2(est::varEstimate, R::Matrix{Bool}, egls::Bool=false)
	# TODO: Add small r from Lutkepohl 5.2
	# The original data are not changed, due to very different structure in the estimation (vectorisation)
	# The matrix R as the argument has to be of the size of the coefficients
	# Y stay the same

	# Naming conventions, this does not eat up memory, it is just renaming for more readability, 
	# it is parsed out
	Z = est.X'
	Y = est.Y
	Σ = est.Σ
	L = est.lags
	K = est.vars
	k = est.obs-est.lags

	# Temporary restriction to restrict betas only to 0
	r = fill(0.0, prod(size(R))) 

	z = vec(Y) - kron(eye(K), Z')*r
	R = getR(R')

	if egls
		Σ1 = inv(Σ)
		γ = R'*kron(Σ1, Z*Z')*R \ R'*kron(Σ1, Z)*z
	else
		γ = (R'*kron(eye(K), Z*Z')*R) \ R'*kron(eye(K), Z)*z
	end
	β = R*γ + r
	est.C = reshape(β, L*K+1, K)

	est.Σ = (est.X*est.C-est.Y)'*(est.X*est.C-est.Y) / k
	return est
end


function Phi(estimate::varEstimate, H)
	phi = zeros(estimate.vars, estimate.vars, H)
	phi[:,:,1] = eye(estimate.vars)

	for j=2:H
		k = j > estimate.lags ? estimate.lags + 1 : j
		for i=1:(k-1)
			phi[:,:,j] += phi[:,:,j-i]*Clag(estimate, i)
	 	end
	end
	estimate.Phi = phi
	estimate.HPhi = H
	return phi
end

function Psi(estimate::varEstimate, H)
	Phi(estimate, H)
	psi = deepcopy(estimate.Phi)
	P = chol(estimate.Σ)
	for i=1:H
		psi[:,:,i] = P*psi[:,:,i]
	end
	estimate.Psi = psi
	estimate.HPsi = H
	return psi
end

# function fevd(estimate::varEstimate, H)
# 	Psi(estimate, H)
# 	FEVD = [sum(estimate.Psi[i,j,:].^2) for i=1:estimate.vars, j=1:estimate.vars]
# 	FEVD = apply(hcat,[FEVD[:,i]/sum(FEVD[:,i]) for i=1:estimate.vars])
# 	return FEVD
# end

function show(io::IO, a::varEstimate)
	line = "--------------------------------------------------------"
	println(io, line)
	println(io, "                    VAR ESTIMATE")
	println(io, line)
	print(io, "Series: ")
	i=1
	while i < (length(a.seriesNames))
		print(io, (a.seriesNames)[i])
		print(io, ", ")
		i += 1
	end
	print(io, a.seriesNames[end])
	print(io, "\n")

	print(io, "Lags: ")
	println(io, a.lags)

	print(io, "Type: ")
	println(io, a.typ)

	println(io, line)

	if (a.typ == "Const") || (a.typ == "Trend")
		println(io, a.typ)
		println(io, mapslices((x)->join(x, "\n"), mapslices((x)->join(x, "  "), map((x)->format(x, precision = 2, signed = true), a.C[1,:]), [2]), [1])[1,1])
	elseif a.typ == "Const and trend"
		println(io, a.typ)
		println(io, mapslices((x)->join(x, "\n"), mapslices((x)->join(x, "  "), map((x)->format(x, precision = 2, signed = true), a.C[1:2,:]), [2]), [1])[1,1])
	end

	for i=1:a.lags
		println(io, line)
		print(io,"Lag ")
		println(io, i)
		println(io, line)
		println(io, mapslices((x)->join(x, "\n"), mapslices((x)->join(x, "  "), map((x)->format(x, precision = 2, signed = true), Clag(a,i)), [2]), [1])[1,1])
	end
end

function simulateVAR(estimate::varEstimate, N, burnout=1000)
	d = MvNormal(estimate.Σ)
	errors = rand(d, N+burnout)
    simulation = zeros((N+burnout, estimate.vars))
    for i=(estimate.lags+1):(N + burnout)
        simulation[i, :] = estimate.C[1,:]
        for j=1:estimate.lags
            simulation[i, :] += simulation[i-j,:] * estimate.C[(1:estimate.vars)+1+(j-1)*estimate.vars,:]
        end
        simulation[i, :] += errors[:, i]'
    end
    return simulation[(burnout+1):(size(simulation)[1]), :]
end
