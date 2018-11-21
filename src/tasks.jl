abstract type AbstractMotionTask end

struct SpatialAccelerationTask <: AbstractMotionTask
    path::TreePath{RigidBody{Float64}, Joint{Float64}}
    jacobian::GeometricJacobian{Matrix{Float64}}
    desired::Base.RefValue{SpatialAcceleration{Float64}}

    function SpatialAccelerationTask(
                mechanism::Mechanism, # TODO: would be nice to get rid of this; possible if compact Jacobians were available
                path::TreePath{RigidBody{Float64}, Joint{Float64}};
                frame::CartesianFrame3D = default_frame(target(path)))
        nv = num_velocities(mechanism)
        bodyframe = default_frame(target(path))
        baseframe = default_frame(source(path))
        jacobian = GeometricJacobian(bodyframe, baseframe, frame, zeros(3, nv), zeros(3, nv))
        desired = Ref{SpatialAcceleration{Float64}}(zero(SpatialAcceleration{Float64}, bodyframe, baseframe, frame))
        new(path, jacobian, desired)
    end
end

dimension(task::SpatialAccelerationTask) = 6

function setdesired!(task::SpatialAccelerationTask, desired::SpatialAcceleration)
    @framecheck task.desired[].body desired.body
    @framecheck task.desired[].base desired.base
    @framecheck task.desired[].frame desired.frame
    task.desired[] = desired
    nothing
end

function task_error(task::SpatialAccelerationTask, qpmodel, state::MechanismState, v̇::AbstractVector{Parametron.Variable})
    J = Parameter(task.jacobian, qpmodel) do jac
        world_to_desired = inv(transform_to_root(state, task.desired[].frame))
        geometric_jacobian!(jac, state, task.path, world_to_desired)
    end
    J̇v = Parameter{SpatialAcceleration{Float64}}(qpmodel) do
        bias = -bias_acceleration(state, source(task.path)) + bias_acceleration(state, target(task.path))
        transform(state, bias, task.desired[].frame)
    end
    desired = Parameter{SpatialAcceleration{Float64}}(() -> task.desired[], qpmodel)
    @expression [
        angular(J) * v̇ + angular(J̇v) - angular(desired);
        linear(J) * v̇ + linear(J̇v) - linear(desired)]
end


struct AngularAccelerationTask <: AbstractMotionTask
    path::TreePath{RigidBody{Float64}, Joint{Float64}}
    jacobian::GeometricJacobian{Matrix{Float64}}
    desired::Base.RefValue{FreeVector3D{SVector{3, Float64}}}

    function AngularAccelerationTask(
                mechanism::Mechanism, # TODO: would be nice to get rid of this; possible if compact Jacobians were available
                path::TreePath{RigidBody{Float64}, Joint{Float64}};
                frame::CartesianFrame3D = default_frame(target(path)))
        nv = num_velocities(mechanism)
        bodyframe = default_frame(target(path))
        baseframe = default_frame(source(path))
        jacobian = GeometricJacobian(bodyframe, baseframe, frame, zeros(3, nv), zeros(3, nv))
        desired = Ref(FreeVector3D(frame, 0.0, 0.0, 0.0))
        new(path, jacobian, desired)
    end
end

dimension(task::AngularAccelerationTask) = 3

function setdesired!(task::AngularAccelerationTask, desired::FreeVector3D)
    @framecheck task.desired[].frame desired.frame
    task.desired[] = desired
    nothing
end

function task_error(task::AngularAccelerationTask, qpmodel, state::MechanismState, v̇::AbstractVector{Parametron.Variable})
    J = Parameter(task.jacobian, qpmodel) do jac
        world_to_desired = inv(transform_to_root(state, task.desired[].frame))
        geometric_jacobian!(jac, state, task.path, world_to_desired)
    end
    J̇v = Parameter{SpatialAcceleration{Float64}}(qpmodel) do
        bias = -bias_acceleration(state, source(task.path)) + bias_acceleration(state, target(task.path))
        transform(state, bias, task.desired[].frame)
    end
    desired = Parameter{SVector{3, Float64}}(() -> task.desired[].v, qpmodel)
    @expression angular(J) * v̇ + angular(J̇v) - desired
end

struct LinearAccelerationTask <: AbstractMotionTask
    path::TreePath{RigidBody{Float64}, Joint{Float64}}
    jacobian::GeometricJacobian{Matrix{Float64}}
    desired::Base.RefValue{FreeVector3D{SVector{3, Float64}}}

    function LinearAccelerationTask(
                mechanism::Mechanism,
                path::TreePath{RigidBody{Float64}, Joint{Float64}};
                frame::CartesianFrame3D = default_frame(target(path)))
        nv = num_velocities(mechanism)
        bodyframe = default_frame(target(path))
        baseframe = default_frame(source(path))
        jacobian = GeometricJacobian(bodyframe, baseframe, frame, zeros(3, nv), zeros(3, nv))
        desired = Ref(FreeVector3D(frame, 0.0, 0.0, 0.0))
        new(path, jacobian, desired)
    end
end

dimension(task::LinearAccelerationTask) = 3

function setdesired!(task::LinearAccelerationTask, desired::FreeVector3D)
    @framecheck task.desired[].frame desired.frame
    task.desired[] = desired
    nothing
end

function task_error(task::LinearAccelerationTask, qpmodel, state::MechanismState, v̇::AbstractVector{Parametron.Variable})
    J = Parameter(task.jacobian, qpmodel) do jac
        world_to_desired = inv(transform_to_root(state, task.desired[].frame))
        geometric_jacobian!(jac, state, task.path, world_to_desired)
    end
    J̇v = Parameter{SpatialAcceleration{Float64}}(qpmodel) do
        bias = -bias_acceleration(state, source(task.path)) + bias_acceleration(state, target(task.path))
        transform(state, bias, task.desired[].frame)
    end
    desired = Parameter{SVector{3, Float64}}(() -> task.desired[].v, qpmodel)
    @expression linear(J) * v̇ + linear(J̇v) - desired
end

struct PointAccelerationTask <: AbstractMotionTask
    path::TreePath{RigidBody{Float64}, Joint{Float64}}
    jacobian::PointJacobian{Matrix{Float64}}
    point::Point3D{SVector{3, Float64}}
    desired::Base.RefValue{FreeVector3D{SVector{3, Float64}}}

    function PointAccelerationTask(
                mechanism::Mechanism,
                path::TreePath{RigidBody{Float64}, Joint{Float64}},
                point::Point3D)
        nv = num_velocities(mechanism)
        bodyframe = default_frame(target(path))
        baseframe = default_frame(source(path))
        @framecheck point.frame bodyframe
        jacobian = PointJacobian(baseframe, zeros(3, nv))
        desired = Ref(FreeVector3D(baseframe, 0.0, 0.0, 0.0))
        new(path, jacobian, point, desired)
    end
end

dimension(task::PointAccelerationTask) = 3

function setdesired!(task::PointAccelerationTask, desired::FreeVector3D)
    @framecheck task.desired[].frame desired.frame
    task.desired[] = desired
    nothing
end

function task_error(task::PointAccelerationTask, qpmodel, state::MechanismState, v̇::AbstractVector{Parametron.Variable})
    frame = task.desired[].frame
    state_param = Parameter(identity, state, qpmodel)
    point_in_task_frame = @expression transform(state_param, task.point, frame)
    J = Parameter(task.jacobian, qpmodel) do jac
        point_jacobian!(jac, state, task.path, point_in_task_frame())
        jac
    end
    J̇v = Parameter{SpatialAcceleration{Float64}}(qpmodel) do
        bias = -bias_acceleration(state, source(task.path)) + bias_acceleration(state, target(task.path))
        transform(state, bias, frame)
    end
    desired = Parameter{SVector{3, Float64}}(() -> task.desired[].v, qpmodel)
    T = @expression transform(state_param, relative_twist(state_param, target(task.path), source(task.path)), frame)
    @framecheck T().frame frame
    ω = @expression angular(T)
    ṗ = @expression point_velocity(T, point_in_task_frame)
    @expression ω × ṗ.v + J.J * v̇ + (angular(J̇v) × point_in_task_frame.v + linear(J̇v)) - desired
end

struct JointAccelerationTask{JT<:JointType{Float64}} <: AbstractMotionTask
    joint::Joint{Float64, JT}
    desired::Vector{Float64}

    function JointAccelerationTask(joint::Joint{Float64, JT}) where {JT<:JointType{Float64}}
        new{JT}(joint, zeros(num_velocities(joint)))
    end
end

dimension(task::JointAccelerationTask) = length(task.desired)
setdesired!(task::JointAccelerationTask, desired) = set_velocity!(task.desired, task.joint, desired)

function task_error(task::JointAccelerationTask, qpmodel, state::MechanismState, v̇::AbstractVector{Parametron.Variable})
    desired = Parameter(identity, task.desired, qpmodel)
    v̇joint = v̇[velocity_range(state, task.joint)]
    @expression v̇joint - desired
end


struct MomentumRateTask <: AbstractMotionTask
    momentum_matrix::MomentumMatrix{Matrix{Float64}}
    desired::Base.RefValue{Wrench{Float64}}

    function MomentumRateTask(mechanism::Mechanism, centroidalframe::CartesianFrame3D)
        nv = num_velocities(mechanism)
        momentum_matrix = MomentumMatrix(centroidalframe, zeros(3, nv), zeros(3, nv))
        desired = Ref(zero(Wrench{Float64}, centroidalframe))
        new(momentum_matrix, desired)
    end
end

function momentum_rate_task_params(task, qpmodel, state, v̇)
    # TODO: repeated computation of world_to_centroidal, but running into inference issues if that computation
    # is extracted out into its own Parameter
    centroidalframe = task.momentum_matrix.frame
    A = Parameter(task.momentum_matrix, qpmodel) do A
        com = center_of_mass(state)
        centroidal_to_world = Transform3D(centroidalframe, com.frame, com.v)
        world_to_centroidal = inv(centroidal_to_world)
        momentum_matrix!(A, state, world_to_centroidal)
    end
    Ȧv = Parameter{Wrench{Float64}}(qpmodel) do
        com = center_of_mass(state)
        centroidal_to_world = Transform3D(centroidalframe, com.frame, com.v)
        world_to_centroidal = inv(centroidal_to_world)
        transform(momentum_rate_bias(state), world_to_centroidal)
    end
    A, Ȧv
end

dimension(task::MomentumRateTask) = 6

function setdesired!(task::MomentumRateTask, desired::Wrench)
    @framecheck task.momentum_matrix.frame desired.frame
    task.desired[] = desired
end

function task_error(task::MomentumRateTask, qpmodel, state::MechanismState, v̇::AbstractVector{Parametron.Variable})
    A, Ȧv = momentum_rate_task_params(task, qpmodel, state, v̇)
    desired = Parameter{Wrench{Float64}}(() -> task.desired[], qpmodel)
    @expression [
        angular(A) * v̇ + angular(Ȧv) - angular(desired);
        linear(A) * v̇ + linear(Ȧv) - linear(desired)]
end


struct LinearMomentumRateTask <: AbstractMotionTask
    momentum_matrix::MomentumMatrix{Matrix{Float64}}
    desired::Base.RefValue{FreeVector3D{SVector{3, Float64}}}

    function LinearMomentumRateTask(mechanism::Mechanism, centroidalframe::CartesianFrame3D = CartesianFrame3D())
        nv = num_velocities(mechanism)
        momentum_matrix = MomentumMatrix(centroidalframe, zeros(3, nv), zeros(3, nv))
        desired = Ref(FreeVector3D(centroidalframe, 0.0, 0.0, 0.0))
        new(momentum_matrix, desired)
    end
end

dimension(task::LinearMomentumRateTask) = 3

function setdesired!(task::LinearMomentumRateTask, desired::FreeVector3D)
    @framecheck task.momentum_matrix.frame desired.frame
    task.desired[] = desired
end

function task_error(task::LinearMomentumRateTask, qpmodel, state::MechanismState, v̇::AbstractVector{Parametron.Variable})
    A, Ȧv = momentum_rate_task_params(task, qpmodel, state, v̇)
    desired = Parameter{SVector{3, Float64}}(() -> task.desired[].v, qpmodel)
    @expression linear(A) * v̇ + linear(Ȧv) - desired
end
