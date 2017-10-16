using MomentumBasedControl
using RigidBodyDynamics
using RigidBodyDynamics.OdeIntegrators
using ValkyrieRobot.BipedControlUtil
using ValkyrieRobot
using StaticArrays
using Rotations
using Base.Test

val = Valkyrie()
mechanism = val.mechanism
floatingjoint = val.basejoint
controller = MomentumBasedController(mechanism)
contacts = add_mechanism_contacts!(controller)
jointacceltasks = add_mechanism_joint_accel_tasks!(controller)
state = MechanismState(mechanism)
controllerstate = MomentumBasedControllerState(state)

@testset "zero velocity free fall" begin
    srand(5354)
    zero!(state)
    rand_configuration!(state)
    regularize_joint_accels!(controller, 1.)
    disable!(jointacceltasks[floatingjoint])
    control(controller, 0., controllerstate)
    accels = Dict{RigidBody{Float64}, SpatialAcceleration{Float64}}()
    spatial_accelerations!(accels, state, controller.result.v̇)
    for joint in tree_joints(mechanism)
        if joint == floatingjoint
            baseaccel = relative_acceleration(accels, val.pelvis, root_body(mechanism))
            baseaccel = transform(state, baseaccel, frame_after(floatingjoint))
            angularaccel = FreeVector3D(baseaccel.frame, baseaccel.angular)
            @test isapprox(angularaccel, FreeVector3D(frame_after(floatingjoint), zeros(SVector{3})), atol = 1e-6)
            linearaccel = FreeVector3D(baseaccel.frame, baseaccel.linear)
            linearaccel = transform_to_root(state, linearaccel.frame) * linearaccel
            @test isapprox(linearaccel, mechanism.gravitational_acceleration; atol = 1e-6)
        else
            v̇joint = controller.result.v̇[velocity_range(state, joint)]
            @test isapprox(v̇joint, zeros(num_velocities(joint)); atol = 1e-6)
        end
    end
end

@testset "achievable momentum rate" begin
    srand(1)
    for p in linspace(0., 1., 5)
        rand!(state)
        com = center_of_mass(state)
        centroidal_to_world = Transform3D(centroidal_frame(controller), com.frame, com.v)
        world_to_centroidal = inv(centroidal_to_world)
        reset!(controller)
        reset!(controllerstate)

        # set random active contacts and random achievable wrench
        fg = world_to_centroidal * (mass(mechanism) * mechanism.gravitational_acceleration)
        ḣdes = Wrench(zero(fg), fg)
        for foot in values(val.feet)
            for contactsettings in contacts[foot]
                active = rand() < p
                if active
                    @assert num_basis_vectors(contactsettings) >= 4 # test relies on this fact
                    r = contactsettings.point
                    μ = rand()
                    normal = FreeVector3D(r.frame, normalize(randn(SVector{3})))
                    set!(contactsettings, 0., μ, normal)
                    fnormal = 50. * rand()
                    μreduced = sqrt(2) / 2 * μ # due to polyhedral inner approximation; assumes 4 basis vectors or more
                    ftangential = μreduced * fnormal * rand() * cross(normal, FreeVector3D(normal.frame, normalize(randn(SVector{3}))))
                    f = fnormal * normal + ftangential
                    @assert isapprox(ftangential ⋅ normal, 0., atol = 1e-12)
                    @assert norm(f - (normal ⋅ f) * normal) ≤ μreduced * (normal ⋅ f)
                    wrench = Wrench(r, f)
                    ḣdes += transform(wrench, world_to_centroidal * transform_to_root(state, wrench.frame))
                else
                    disable!(contactsettings)
                end
            end
        end
        add!(controller, MomentumRateTask(ḣdes, eye(SMatrix{3, 3}), eye(SMatrix{3, 3}), 1.))
        control(controller, 0., controllerstate)

        # Ensure that desired momentum rate is achieved.
        ḣ = Wrench(momentum_matrix(state), controller.result.v̇) + momentum_rate_bias(state)
        ḣ = transform(ḣ, world_to_centroidal)
        @test isapprox(ḣdes, ḣ; atol = 1e-3)
    end
end

@testset "spatial acceleration" begin
    srand(533)
    rand!(state)
    controller = MomentumBasedController(mechanism)
    body = val.feet[left]
    base = val.palms[right]
    frame = default_frame(base)
    task = SpatialAccelerationTask(num_velocities(mechanism), path(mechanism, base, body), frame, eye(3), eye(3))
    add!(controller, task)

    accels = Dict{RigidBody{Float64}, SpatialAcceleration{Float64}}()
    for weight in [1., Inf]
        reset!(controller)
        reset!(controllerstate)
        if isinf(weight)
            regularize_joint_accels!(controller, 1.)
        end
        desiredaccel = rand(SpatialAcceleration{Float64}, default_frame(body), default_frame(base), frame)
        set!(task, desiredaccel, weight)
        control(controller, 0., controllerstate)
        v̇ = controller.result.v̇
        spatial_accelerations!(accels, state, v̇)
        accel = relative_acceleration(accels, body, base)
        accel = transform(state, accel, frame)
        @test isapprox(accel, desiredaccel, atol = 1e-8)
    end
end

@testset "Δt" begin
    srand(2533)
    rand!(state)
    Δt = 1.
    controller = MomentumBasedController(mechanism, Δt)
    contacts = add_mechanism_contacts!(controller)
    tasks = add_mechanism_joint_accel_tasks!(controller)

    randomize = () -> begin
        for task in values(tasks)
            set!(task, rand(), 1.)
        end
        for (body, contactsettings) in contacts
            for contactpointsetting in contactsettings
                frame = default_frame(body)
                set!(contactpointsetting, 1e-3, 100., rand(FreeVector3D, Float64, frame))
            end
        end
        rand!(state)
    end

    controllerstate = MomentumBasedControllerState(state)
    t0 = 2.
    randomize()
    τ1 = copy(control(controller, t0, controllerstate))
    for t in linspace(t0, t0 + Δt - 1e-3, 10)
        randomize()
        τ = control(controller, t, controllerstate)
        @test all(τ1 .== τ)
    end
    randomize()
    @test any(τ1 .!= control(controller, t0 + Δt + 1e-3, controllerstate))
end

# notebooks
@testset "example notebooks" begin
    using NBInclude
    notebookdir = Pkg.dir("MomentumBasedControl", "notebooks")
    for file in readdir(notebookdir)
        name, ext = splitext(file)
        if lowercase(ext) == ".ipynb"
            @testset "$name" begin
                println("Testing $name.")
                let
                    nbinclude(joinpath(notebookdir, file), regex = r"^((?!\#NBSKIP).)*$"s)
                end
            end
        end
    end
end
