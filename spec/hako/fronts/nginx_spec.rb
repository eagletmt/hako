require 'spec_helper'
require 'hako/fronts/nginx'
require 'hako/front_config'

RSpec.describe Hako::Fronts::Nginx do
  let(:front) { described_class.new(front_config) }
  let(:front_config) { Hako::FrontConfig.new(raw_config) }
  let(:raw_config) do
    {
      'type' => 'nginx',
      'image_tag' => 'hako-nginx',
      's3' => {
        'region' => 'ap-northeast-1',
        'bucket' => 'nanika',
        'prefix' => 'hako/front_config',
      },
      'extra' => extra,
    }
  end
  let(:extra) { {} }

  describe '#generate_config' do
    it 'generates nginx config' do
      expect(front.generate_config(3000)).to include('proxy_pass http://app:3000;')
    end

    describe 'allow_only_from' do
      it 'adds allow directive' do
        extra['locations'] = {
          '/' => {
            'allow_only_from' => ['10.0.0.0/24'],
          },
        }
        expect(front.generate_config(3000)).to include('allow 10.0.0.0/24;')
        expect(front.generate_config(3000)).to include('deny all;')
      end

      it "doesn't add deny all directive" do
        expect(front.generate_config(3000)).to_not include('deny all;')
      end
    end
  end
end
