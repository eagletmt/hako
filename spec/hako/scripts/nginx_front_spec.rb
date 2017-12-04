# frozen_string_literal: true

require 'spec_helper'
require 'hako/app_container'
require 'hako/scripts/nginx_front'

RSpec.describe Hako::Scripts::NginxFront do
  let(:script) { described_class.new(app, options, dry_run: false) }
  let(:app) { double('Hako::Application', id: 'nanika') }
  let(:app_container) { Hako::AppContainer.new(app, {}, dry_run: false) }
  let(:backend_port) { 3000 }
  let(:front_container) { Hako::Container.new(app, {}, dry_run: false) }
  let(:s3_region) { 'ap-northeast-1' }
  let(:s3_bucket) { 'nanika' }
  let(:s3_prefix) { 'hako/front_config' }
  let(:options) do
    {
      'type' => 'nginx',
      's3' => {
        'region' => s3_region,
        'bucket' => s3_bucket,
        'prefix' => s3_prefix,
      },
      'backend_port' => backend_port,
    }
  end
  let(:containers) { { 'app' => app_container, 'front' => front_container } }
  let(:s3_client) { double('Aws::S3::Client') }
  let(:uploaded_config) { StringIO.new }

  before do
    allow(script).to receive(:s3_client).and_return(s3_client)
    allow(s3_client).to receive(:put_object) { |args| uploaded_config.write(args[:body]) }
  end

  describe '#deploy_starting' do
    it 'configures environment variables' do
      env = {
        'AWS_DEFAULT_REGION' => s3_region,
        'S3_CONFIG_BUCKET' => s3_bucket,
        'S3_CONFIG_KEY' => "#{s3_prefix}/#{app.id}.conf",
      }
      expect { script.deploy_starting(containers) }.to change {
        containers['front'].definition['env']
      }.from({}).to(env)
    end
  end

  describe '#deploy_started' do
    let(:front_port) { 10000 }

    it 'configures links' do
      expect { script.deploy_started(containers, front_port) }.to change {
        containers['front'].links
      }.from([]).to(['app:backend'])
    end

    it 'generates nginx config' do
      expect(script.deploy_started(containers, front_port)).to eq(true)
      expect(uploaded_config.string).to include("proxy_pass http://backend:#{backend_port};")
    end

    it 'configures port mappings' do
      port_mapping = {
        container_port: 80,
        host_port: front_port,
        protocol: 'tcp',
      }
      expect { script.deploy_started(containers, front_port) }.to change {
        containers['front'].port_mappings
      }.from([]).to([port_mapping])
    end

    it "doesn't add deny all directive" do
      expect(script.deploy_started(containers, front_port)).to eq(true)
      expect(uploaded_config.string).to_not include('deny all;')
    end

    context 'when front_port is nil because of container networking mode' do
      it 'skips links' do
        expect { script.deploy_started(containers, nil) }.to_not change {
          containers['front'].links
        }.from([])
      end

      it 'generates nginx config to proxy to localhost' do
        expect(script.deploy_started(containers, nil)).to eq(true)
        expect(uploaded_config.string).to include("proxy_pass http://localhost:#{backend_port};")
      end
    end

    context 'with allow_only_from' do
      before do
        options['locations'] = {
          '/' => {
            'allow_only_from' => ['127.0.0.1', ['10.0.0.0/24']],
          },
        }
      end

      it 'adds allow directive' do
        expect(script.deploy_started(containers, front_port)).to eq(true)
        expect(uploaded_config.string).to include('allow 127.0.0.1;')
        expect(uploaded_config.string).to include('allow 10.0.0.0/24;')
        expect(uploaded_config.string).to include('deny all;')
      end
    end

    context 'with client_max_body_size' do
      before do
        options['client_max_body_size'] = '1G'
      end

      it 'adds client_max_body_size directive' do
        expect(script.deploy_started(containers, front_port)).to eq(true)
        expect(uploaded_config.string).to include('client_max_body_size 1G;')
      end
    end
  end
end
