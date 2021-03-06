# frozen_string_literal: true

class TestSuiteComparerEntity < Grape::Entity
  expose :name
  expose :total_status, as: :status

  expose :summary do
    expose :total_count, as: :total
    expose :resolved_count, as: :resolved
    expose :failed_count, as: :failed
    expose :error_count, as: :errored
  end

  expose :new_failures, using: TestCaseEntity do |suite|
    suite.limited_tests.new_failures
  end

  expose :existing_failures, using: TestCaseEntity do |suite|
    suite.limited_tests.existing_failures
  end

  expose :resolved_failures, using: TestCaseEntity do |suite|
    suite.limited_tests.resolved_failures
  end

  expose :new_errors, using: TestCaseEntity do |suite|
    suite.limited_tests.new_errors
  end

  expose :existing_errors, using: TestCaseEntity do |suite|
    suite.limited_tests.existing_errors
  end

  expose :resolved_errors, using: TestCaseEntity do |suite|
    suite.limited_tests.resolved_errors
  end
end
