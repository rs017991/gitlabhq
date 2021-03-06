# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Middleware::Multipart do
  include MultipartHelpers

  describe '#call' do
    let(:app) { double(:app) }
    let(:middleware) { described_class.new(app) }
    let(:secret) { Gitlab::Workhorse.secret }
    let(:issuer) { 'gitlab-workhorse' }

    subject do
      env = post_env(
        rewritten_fields: rewritten_fields,
        params: params,
        secret: secret,
        issuer: issuer
      )
      middleware.call(env)
    end

    before do
      stub_feature_flags(upload_middleware_jwt_params_handler: false)
    end

    context 'remote file mode' do
      let(:mode) { :remote }

      it_behaves_like 'handling all upload parameters conditions'

      context 'and a path set' do
        include_context 'with one temporary file for multipart'

        let(:rewritten_fields) { rewritten_fields_hash('file' => uploaded_filepath) }
        let(:params) { upload_parameters_for(key: 'file', filename: filename, remote_id: remote_id).merge('file.path' => '/should/not/be/read') }

        it 'builds an UploadedFile' do
          expect_uploaded_files(original_filename: filename, remote_id: remote_id, size: uploaded_file.size, params_path: %w(file))

          subject
        end
      end
    end

    context 'local file mode' do
      let(:mode) { :local }

      it_behaves_like 'handling all upload parameters conditions'

      context 'when file is' do
        include_context 'with one temporary file for multipart'

        let(:allowed_paths) { [Dir.tmpdir] }

        before do
          expect_next_instance_of(::Gitlab::Middleware::Multipart::Handler) do |handler|
            expect(handler).to receive(:allowed_paths).and_return(allowed_paths)
          end
        end

        context 'in allowed paths' do
          let(:rewritten_fields) { rewritten_fields_hash('file' => uploaded_filepath) }
          let(:params) { upload_parameters_for(filepath: uploaded_filepath, key: 'file', filename: filename) }

          it 'builds an UploadedFile' do
            expect_uploaded_files(filepath: uploaded_filepath, original_filename: filename, size: uploaded_file.size, params_path: %w(file))

            subject
          end
        end

        context 'not in allowed paths' do
          let(:allowed_paths) { [] }

          let(:rewritten_fields) { rewritten_fields_hash('file' => uploaded_filepath) }
          let(:params) { upload_parameters_for(filepath: uploaded_filepath, key: 'file') }

          it 'returns an error' do
            result = subject

            expect(result[0]).to eq(400)
            expect(result[2]).to include('insecure path used')
          end
        end
      end
    end

    context 'with dummy params in remote mode' do
      let(:rewritten_fields) { { 'file' => 'should/not/be/read' } }
      let(:params) { upload_parameters_for(key: 'file') }
      let(:mode) { :remote }

      context 'with an invalid secret' do
        let(:secret) { 'INVALID_SECRET' }

        it { expect { subject }.to raise_error(JWT::VerificationError) }
      end

      context 'with an invalid issuer' do
        let(:issuer) { 'INVALID_ISSUER' }

        it { expect { subject }.to raise_error(JWT::InvalidIssuerError) }
      end

      context 'with invalid rewritten field key' do
        invalid_keys = [
          '[file]',
          ';file',
          'file]',
          ';file]',
          'file]]',
          'file;;'
        ]

        invalid_keys.each do |invalid_key|
          context invalid_key do
            let(:rewritten_fields) { { invalid_key => 'should/not/be/read' } }

            it { expect { subject }.to raise_error(RuntimeError, "invalid field: \"#{invalid_key}\"") }
          end
        end
      end

      context 'with invalid key in parameters' do
        include_context 'with one temporary file for multipart'

        let(:rewritten_fields) { rewritten_fields_hash('file' => uploaded_filepath) }
        let(:params) { upload_parameters_for(filepath: uploaded_filepath, key: 'wrong_key', filename: filename, remote_id: remote_id) }

        it 'builds no UploadedFile' do
          expect(app).to receive(:call) do |env|
            received_params = get_params(env)
            expect(received_params['file']).to be_nil
            expect(received_params['wrong_key']).to be_nil
          end

          subject
        end
      end

      context 'with invalid key in header' do
        include_context 'with one temporary file for multipart'

        RSpec.shared_examples 'rejecting the invalid key' do |key_in_header:, key_in_upload_params:, error_message:|
          let(:rewritten_fields) { rewritten_fields_hash(key_in_header => uploaded_filepath) }
          let(:params) { upload_parameters_for(filepath: uploaded_filepath, key: key_in_upload_params, filename: filename, remote_id: remote_id) }

          it 'raises an error' do
            expect { subject }.to raise_error(RuntimeError, error_message)
          end
        end

        it_behaves_like 'rejecting the invalid key',
                        key_in_header: 'user[avatar',
                        key_in_upload_params: 'user[avatar]',
                        error_message: 'invalid field: "user[avatar"'
        it_behaves_like 'rejecting the invalid key',
                        key_in_header: '[user]avatar',
                        key_in_upload_params: 'user[avatar]',
                        error_message: 'invalid field: "[user]avatar"'
        it_behaves_like 'rejecting the invalid key',
                        key_in_header: 'user[]avatar',
                        key_in_upload_params: 'user[avatar]',
                        error_message: 'invalid field: "user[]avatar"'
        it_behaves_like 'rejecting the invalid key',
                        key_in_header: 'user[avatar[image[url]]]',
                        key_in_upload_params: 'user[avatar]',
                        error_message: 'invalid field: "user[avatar[image[url]]]"'
        it_behaves_like 'rejecting the invalid key',
                        key_in_header: '[]',
                        key_in_upload_params: 'user[avatar]',
                        error_message: 'invalid field: "[]"'
        it_behaves_like 'rejecting the invalid key',
                        key_in_header: 'x' * 11000,
                        key_in_upload_params: 'user[avatar]',
                        error_message: "invalid field: \"#{'x' * 11000}\""
      end

      context 'with key with unbalanced brackets in header' do
        include_context 'with one temporary file for multipart'

        let(:invalid_key) { 'user[avatar' }
        let(:rewritten_fields) { rewritten_fields_hash( invalid_key => uploaded_filepath) }
        let(:params) { upload_parameters_for(filepath: uploaded_filepath, key: 'user[avatar]', filename: filename, remote_id: remote_id) }

        it 'builds no UploadedFile' do
          expect(app).not_to receive(:call)

          expect { subject }.to raise_error(RuntimeError, "invalid field: \"#{invalid_key}\"")
        end
      end
    end
  end
end
