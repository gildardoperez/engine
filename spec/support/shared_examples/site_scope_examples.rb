RSpec.shared_examples_for 'model scoped by a site' do

  it { allow(model).to receive(:site) }

  describe 'touch' do

    let(:date) { Time.zone.local(2015, 4, 1, 12, 0, 0) }
    let(:attribute) { :template_version }

    subject { model.save! }

    it 'updates the updated_at attribute of the site' do
      Timecop.freeze(date) do
        expect { subject }.to change { site.updated_at }.to date
      end
    end

    it 'updates the template_version attribute of the site' do
      Timecop.freeze(date) do
        expect { subject }.to change { site.send(attribute) }.to date
      end
    end

  end

end
