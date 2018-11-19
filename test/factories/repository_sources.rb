FactoryBot.define do
  factory :repository_source do
    association :repository
    provider { "gitbook" }
    url { "https://github.com/huacnlee/test.git" }
  end
end