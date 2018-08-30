# frozen_string_literal: true

require 'spec_helper'
require 'hako/application'
require 'hako/definition_loader'
require 'hako/loader'
require 'hako/schedulers/ecs'

RSpec.describe Hako::Schedulers::Ecs do
  let(:dry_run) { false }
  let(:tag) { 'latest' }
  let(:containers) { Hako::DefinitionLoader.new(app, dry_run: dry_run).load(tag) }
  let(:scripts) do
    app.definition.fetch('scripts', []).map do |config|
      Hako::Loader.new(Hako::Scripts, 'hako/scripts').load(config.fetch('type')).new(app, config, dry_run: dry_run)
    end
  end
  let(:force) { false }
  let(:scheduler) do
    described_class.new(app.id, app.definition['scheduler'], scripts: scripts, volumes: app.definition.fetch('volumes', {}), force: force, dry_run: dry_run, timeout: nil)
  end
  let(:cluster_arn) { 'arn:aws:ecs:ap-northeast-1:012345678901:cluster/eagletmt' }
  let(:service_arn) { "arn:aws:ecs:ap-northeast-1:012345678901:service/#{app.id}" }
  let(:logger) { Logger.new(logger_io) }
  let(:logger_io) { StringIO.new }

  let(:ecs_client) { double('Aws::ECS::Client') }

  let(:create_service_params) do
    {
      cluster: 'eagletmt',
      service_name: app.id,
      task_definition: task_definition_arn,
      desired_count: 0,
      role: 'ECSServiceRole',
      deployment_configuration: {
        maximum_percent: nil,
        minimum_healthy_percent: nil,
      },
      placement_constraints: [],
      placement_strategy: [],
      scheduling_strategy: nil,
      launch_type: nil,
      platform_version: nil,
      network_configuration: nil,
      health_check_grace_period_seconds: nil,
    }
  end
  let(:update_service_params) do
    {
      cluster: 'eagletmt',
      service: app.id,
      desired_count: 1,
      deployment_configuration: {
        maximum_percent: nil,
        minimum_healthy_percent: nil,
      },
      platform_version: nil,
      network_configuration: nil,
      health_check_grace_period_seconds: nil,
    }
  end
  let(:register_task_definition_params) do
    {
      family: app.id,
      task_role_arn: nil,
      execution_role_arn: nil,
      network_mode: nil,
      container_definitions: [{
        name: 'app',
        image: 'busybox:latest',
        cpu: 32,
        memory: 64,
        memory_reservation: nil,
        links: [],
        port_mappings: [],
        essential: true,
        environment: [],
        docker_labels: { 'cc.wanko.hako.version' => Hako::VERSION },
        mount_points: [],
        command: nil,
        privileged: false,
        linux_parameters: nil,
        volumes_from: [],
        user: nil,
        log_configuration: nil,
        health_check: nil,
        ulimits: nil,
        extra_hosts: nil,
      }],
      volumes: [],
      requires_compatibilities: nil,
      cpu: nil,
      memory: nil,
    }
  end
  let(:dummy_service_response) do
    Aws::ECS::Types::Service.new(
      desired_count: 1,
      events: [],
      deployment_configuration: {
        maximum_percent: nil,
        minimum_healthy_percent: nil,
      },
      placement_constraints: [],
      placement_strategy: [],
      deployments: [Aws::ECS::Types::Deployment.new(status: 'PRIMARY', desired_count: 1, running_count: 1)],
    )
  end
  let(:dummy_container_definition) do
    Aws::ECS::Types::ContainerDefinition.new(
      name: 'app',
      image: 'busybox:latest',
      cpu: 32,
      memory: 64,
      links: [],
      port_mappings: [],
      environment: [],
      docker_labels: { 'cc.wanko.hako.version' => Hako::VERSION },
      mount_points: [],
      privileged: false,
      volumes_from: [],
    )
  end

  before do
    allow(Hako).to receive(:logger).and_return(logger)
    allow(scheduler).to receive(:ecs_client).and_return(ecs_client)
  end

  describe '#deploy' do
    context 'when initial deployment' do
      let(:app) { Hako::Application.new(fixture_root.join('jsonnet', 'ecs.jsonnet')) }
      let(:task_definition_arn) { "arn:aws:ecs:ap-northeast-1:012345678901:task-definition/#{app.id}:1" }

      before do
        allow(ecs_client).to receive(:describe_services).with(cluster: 'eagletmt', services: [app.id]).and_return(Aws::ECS::Types::DescribeServicesResponse.new(failures: [], services: [])).once
        allow(ecs_client).to receive(:describe_task_definition).with(task_definition: app.id).and_raise(Aws::ECS::Errors::ClientException.new(nil, 'Unable to describe task definition')).once
      end

      it 'creates new service' do
        expect(ecs_client).to receive(:register_task_definition).with(register_task_definition_params).and_return(Aws::ECS::Types::RegisterTaskDefinitionResponse.new(
          task_definition: Aws::ECS::Types::TaskDefinition.new(
            task_definition_arn: task_definition_arn,
          ),
        )).once
        expect(ecs_client).to receive(:create_service).with(create_service_params.merge(task_definition: task_definition_arn)).and_return(Aws::ECS::Types::CreateServiceResponse.new(
          service: Aws::ECS::Types::Service.new(
            placement_constraints: [],
            placement_strategy: [],
          ),
        )).once
        expect(ecs_client).to receive(:update_service).with(update_service_params.merge(task_definition: task_definition_arn)).and_return(Aws::ECS::Types::UpdateServiceResponse.new(
          service: Aws::ECS::Types::Service.new(
            cluster_arn: cluster_arn,
            service_arn: service_arn,
            events: [],
          ),
        )).once
        expect(ecs_client).to receive(:describe_services).with(cluster: cluster_arn, services: [service_arn]).and_return(Aws::ECS::Types::DescribeServicesResponse.new(failures: [], services: [dummy_service_response])).once

        scheduler.deploy(containers)
        expect(logger_io.string).to include('Registered task definition')
        expect(logger_io.string).to include('Updated service')
        expect(logger_io.string).to include('Deployment completed')
      end
    end

    context 'when the same service is running' do
      let(:app) { Hako::Application.new(fixture_root.join('jsonnet', 'ecs.jsonnet')) }
      let(:task_definition_arn) { "arn:aws:ecs:ap-northeast-1:012345678901:task-definition/#{app.id}:1" }

      before do
        dummy_service_response.task_definition = task_definition_arn
        allow(ecs_client).to receive(:describe_services).with(cluster: 'eagletmt', services: [app.id]).and_return(Aws::ECS::Types::DescribeServicesResponse.new(failures: [], services: [dummy_service_response])).once
        allow(ecs_client).to receive(:describe_task_definition).with(task_definition: app.id).and_return(Aws::ECS::Types::DescribeTaskDefinitionResponse.new(
          task_definition: Aws::ECS::Types::TaskDefinition.new(
            task_definition_arn: task_definition_arn,
            container_definitions: [dummy_container_definition],
            volumes: [],
          ),
        )).once
      end

      it 'does nothing' do
        scheduler.deploy(containers)
        expect(logger_io.string).to include("Task definition isn't changed")
        expect(logger_io.string).to include("Service isn't changed")
        expect(logger_io.string).to include('Deployment completed')
      end
    end

    context 'when the running service has different desired_count' do
      let(:app) { Hako::Application.new(fixture_root.join('jsonnet', 'ecs.jsonnet')) }
      let(:task_definition_arn) { "arn:aws:ecs:ap-northeast-1:012345678901:task-definition/#{app.id}:1" }

      before do
        dummy_service_response.desired_count = 0
        dummy_service_response.task_definition = task_definition_arn
        allow(ecs_client).to receive(:describe_services).with(cluster: 'eagletmt', services: [app.id]).and_return(Aws::ECS::Types::DescribeServicesResponse.new(failures: [], services: [dummy_service_response])).once
        allow(ecs_client).to receive(:describe_task_definition).with(task_definition: app.id).and_return(Aws::ECS::Types::DescribeTaskDefinitionResponse.new(
          task_definition: Aws::ECS::Types::TaskDefinition.new(
            task_definition_arn: task_definition_arn,
            container_definitions: [dummy_container_definition],
            volumes: [],
          ),
        )).once
      end

      it 'updates service' do
        expect(ecs_client).to receive(:update_service).with(update_service_params.merge(task_definition: task_definition_arn)).and_return(Aws::ECS::Types::UpdateServiceResponse.new(
          service: Aws::ECS::Types::Service.new(
            cluster_arn: cluster_arn,
            service_arn: service_arn,
            events: [],
          ),
        )).once
        expect(ecs_client).to receive(:describe_services).with(cluster: cluster_arn, services: [service_arn]).and_return(Aws::ECS::Types::DescribeServicesResponse.new(failures: [], services: [dummy_service_response])).once
        scheduler.deploy(containers)
      end
    end

    context 'when ther running service has different task definition' do
      let(:app) { Hako::Application.new(fixture_root.join('jsonnet', 'ecs.jsonnet')) }
      let(:running_task_definition_arn) { "arn:aws:ecs:ap-northeast-1:012345678901:task-definition/#{app.id}:1" }
      let(:updated_task_definition_arn) { "arn:aws:ecs:ap-northeast-1:012345678901:task-definition/#{app.id}:2" }

      before do
        dummy_service_response.task_definition = running_task_definition_arn
        allow(ecs_client).to receive(:describe_services).with(cluster: 'eagletmt', services: [app.id]).and_return(Aws::ECS::Types::DescribeServicesResponse.new(failures: [], services: [dummy_service_response])).once
        dummy_container_definition.memory = 1024
        allow(ecs_client).to receive(:describe_task_definition).with(task_definition: app.id).and_return(Aws::ECS::Types::DescribeTaskDefinitionResponse.new(
          task_definition: Aws::ECS::Types::TaskDefinition.new(
            task_definition_arn: running_task_definition_arn,
            container_definitions: [dummy_container_definition],
            volumes: [],
          ),
        )).once
      end
      it 'updates task definition and service' do
        expect(ecs_client).to receive(:register_task_definition).with(register_task_definition_params).and_return(Aws::ECS::Types::RegisterTaskDefinitionResponse.new(
          task_definition: Aws::ECS::Types::TaskDefinition.new(
            task_definition_arn: updated_task_definition_arn,
          ),
        )).once
        expect(ecs_client).to receive(:update_service).with(update_service_params.merge(task_definition: updated_task_definition_arn)).and_return(Aws::ECS::Types::UpdateServiceResponse.new(
          service: Aws::ECS::Types::Service.new(
            cluster_arn: cluster_arn,
            service_arn: service_arn,
            events: [],
          ),
        )).once
        expect(ecs_client).to receive(:describe_services).with(cluster: cluster_arn, services: [service_arn]).and_return(Aws::ECS::Types::DescribeServicesResponse.new(failures: [], services: [dummy_service_response])).once
        scheduler.deploy(containers)
      end
    end

    context 'with ELBv2' do
      let(:app) { Hako::Application.new(fixture_root.join('jsonnet', 'ecs-elbv2.jsonnet')) }
      let(:task_definition_arn) { "arn:aws:ecs:ap-northeast-1:012345678901:task-definition/#{app.id}:1" }
      let(:elb_v2_client) { double('Aws::ElasticLoadBalancingV2::Client') }
      let(:load_balancer_arn) { "arn:aws:elasticloadbalancing:ap-northeast-1:012345678901:loadbalancer/app/hako-#{app.id}/0123456789abcdef" }
      let(:target_group_arn) { "arn:aws:elasticloadbalancing:ap-northeast-1:012345678901:targetgroup/hako-#{app.id}/0123456789abcdef" }
      let(:target_groups) { [] }

      before do
        allow(ecs_client).to receive(:describe_services).with(cluster: 'eagletmt', services: [app.id]).and_return(Aws::ECS::Types::DescribeServicesResponse.new(failures: [], services: [])).once
        allow(ecs_client).to receive(:describe_task_definition).with(task_definition: app.id).and_raise(Aws::ECS::Errors::ClientException.new(nil, 'Unable to describe task definition')).once

        allow(Aws::ElasticLoadBalancingV2::Client).to receive(:new).and_return(elb_v2_client)
        allow(elb_v2_client).to receive(:describe_load_balancers).with(names: ["hako-#{app.id}"]).and_raise(Aws::ElasticLoadBalancingV2::Errors::LoadBalancerNotFound.new(nil, ''))
        allow(elb_v2_client).to receive(:describe_target_groups).with(names: ["hako-#{app.id}"]) {
          if target_groups.empty?
            raise Aws::ElasticLoadBalancingV2::Errors::TargetGroupNotFound.new(nil, '')
          else
            Aws::ElasticLoadBalancingV2::Types::DescribeTargetGroupsOutput.new(target_groups: target_groups)
          end
        }.twice
        listeners = Aws::ElasticLoadBalancingV2::Types::DescribeListenersOutput.new(listeners: []).extend(Aws::PageableResponse)
        listeners.pager = double('Aws::Pager', truncated?: false)
        allow(elb_v2_client).to receive(:describe_listeners).with(load_balancer_arn: load_balancer_arn).and_return(listeners).once
      end

      it 'creates new ELBv2 and service' do
        expect(ecs_client).to receive(:register_task_definition).with(register_task_definition_params).and_return(Aws::ECS::Types::RegisterTaskDefinitionResponse.new(
          task_definition: Aws::ECS::Types::TaskDefinition.new(
            task_definition_arn: task_definition_arn,
          ),
        )).once
        expect(elb_v2_client).to receive(:create_load_balancer).with(
          name: "hako-#{app.id}",
          subnets: ['subnet-11111111', 'subnet-22222222'],
          security_groups: ['sg-11111111'],
          scheme: nil,
          type: nil,
          tags: nil,
        ).and_return(Aws::ElasticLoadBalancingV2::Types::CreateLoadBalancerOutput.new(
          load_balancers: [Aws::ElasticLoadBalancingV2::Types::LoadBalancer.new(
            load_balancer_arn: load_balancer_arn,
            dns_name: "hako-#{app.id}-012345678.ap-northeast-1.elb.amazonaws.com",
          )],
        )).once
        expect(elb_v2_client).to receive(:create_target_group).with(
          name: "hako-#{app.id}",
          port: 80,
          protocol: 'HTTP',
          vpc_id: 'vpc-11111111',
          health_check_path: '/site/sha',
          target_type: nil,
        ) {
          target_group = Aws::ElasticLoadBalancingV2::Types::TargetGroup.new(target_group_arn: target_group_arn)
          target_groups << target_group
          Aws::ElasticLoadBalancingV2::Types::CreateTargetGroupOutput.new(target_groups: [target_group])
        }.once
        expect(elb_v2_client).to receive(:create_listener).with(
          load_balancer_arn: load_balancer_arn,
          protocol: 'HTTP',
          port: 80,
          default_actions: [{ type: 'forward', target_group_arn: target_group_arn }],
        ).and_return(Aws::ElasticLoadBalancingV2::Types::CreateListenerOutput.new(
          listeners: [Aws::ElasticLoadBalancingV2::Types::Listener.new(listener_arn: "arn:aws:elasticloadbalancing:ap-northeast-1:012345678901:listener/app/#{app.id}/0123456789abcdef/0123456789abcdef")],
        )).once
        expect(elb_v2_client).to receive(:create_listener).with(
          load_balancer_arn: load_balancer_arn,
          protocol: 'HTTPS',
          port: 443,
          default_actions: [{ type: 'forward', target_group_arn: target_group_arn }],
          certificates: [{ certificate_arn: 'arn:aws:acm:ap-northeast-1:012345678901:certificate/01234567-89ab-cdef-0123-456789abcdef' }],
        ).and_return(Aws::ElasticLoadBalancingV2::Types::CreateListenerOutput.new(
          listeners: [Aws::ElasticLoadBalancingV2::Types::Listener.new(listener_arn: "arn:aws:elasticloadbalancing:ap-northeast-1:012345678901:listener/app/#{app.id}/0123456789abcdef/abcdef0123456789")],
        )).once
        expect(ecs_client).to receive(:create_service).with(create_service_params.merge(
          task_definition: task_definition_arn,
          load_balancers: [{
            target_group_arn: target_group_arn,
            container_name: 'front',
            container_port: 80,
          }],
        )).and_return(Aws::ECS::Types::CreateServiceResponse.new(
          service: Aws::ECS::Types::Service.new(
            placement_constraints: [],
            placement_strategy: [],
          ),
        )).once
        expect(ecs_client).to receive(:update_service).with(update_service_params.merge(task_definition: task_definition_arn)).and_return(Aws::ECS::Types::UpdateServiceResponse.new(
          service: Aws::ECS::Types::Service.new(
            cluster_arn: cluster_arn,
            service_arn: service_arn,
            events: [],
          ),
        )).once
        expect(ecs_client).to receive(:describe_services).with(cluster: cluster_arn, services: [service_arn]).and_return(Aws::ECS::Types::DescribeServicesResponse.new(failures: [], services: [dummy_service_response])).once

        scheduler.deploy(containers)
        expect(logger_io.string).to include('Registered task definition')
        expect(logger_io.string).to include('Created ELBv2')
        expect(logger_io.string).to include('Created target group')
        expect(logger_io.string).to include('Created listener')
        expect(logger_io.string).to include('Updated service')
        expect(logger_io.string).to include('Deployment completed')
      end
    end
  end
end
