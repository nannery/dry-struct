RSpec.describe Dry::Struct do
  let(:user_type) { Test::User }
  let(:root_type) { Test::SuperUser }

  before do
    module Test
      class BaseAddress < Dry::Struct
        attribute :street, 'strict.string'
      end

      class Address < Dry::Struct
        attribute :city, 'strict.string'
        attribute :zipcode, 'coercible.string'
      end

      # This abstract user guarantees User preserves schema definition
      class AbstractUser < Dry::Struct
        attribute :name, 'coercible.string'
        attribute :age, 'coercible.integer'
        attribute :address, Test::Address
      end

      class User < AbstractUser
      end

      class SuperUser < User
        attributes(root: 'strict.bool')
      end
    end
  end

  it_behaves_like Dry::Struct do
    subject(:type) { root_type }
  end

  shared_examples_for 'typical constructor' do
    it 'raises StructError when attribute constructor failed' do
      expect {
        construct_user(name: :Jane, age: '21', address: nil)
      }.to raise_error(
        Dry::Struct::Error,
        '[Test::Address.new] :city is missing in Hash input'
      )
    end

    it 'passes through values when they are structs already' do
      address = Test::Address.new(city: 'NYC', zipcode: '312')
      user = construct_user(name: 'Jane', age: 21, address: address)

      expect(user.address).to be(address)
    end

    it 'returns itself when an argument is an instance of given class' do
      user = user_type[
        name: :Jane, age: '21', address: { city: 'NYC', zipcode: 123 }
      ]

      expect(construct_user(user)).to be_equal(user)
    end

    it 'creates an empty struct when called without arguments' do
      class Test::Empty < Dry::Struct
        @constructor = Dry::Types['strict.hash'].strict(schema)
      end

      expect { Test::Empty.new }.to_not raise_error
    end
  end

  describe '.new' do
    def construct_user(attributes)
      user_type.new(attributes)
    end

    it_behaves_like 'typical constructor'

    it 'returns new object when an argument is an instance of subclass' do
      user = root_type[
        name: :Jane, age: '21', root: true, address: { city: 'NYC', zipcode: 123 }
      ]

      expect(construct_user(user)).to be_instance_of(user_type)
    end

    context 'with default' do
      it 'resolves missing missing values with defaults' do
        struct = Class.new(Dry::Struct) do
          attribute :name, Dry::Types['strict.string'].default('Jane')
          attribute :admin, Dry::Types['strict.bool'].default(true)
        end

        expect(struct.new.to_h).
          to eql(name: 'Jane', admin: true)
      end

      it "doesn't tolerate missing required keys" do
        struct = Class.new(Dry::Struct) do
          attribute :name, Dry::Types['strict.string'].default('Jane')
          attribute :age, Dry::Types['strict.integer']
        end

        expect { struct.new }.to raise_error(Dry::Struct::Error, /:age is missing in Hash input/)
      end
    end

    it "doesn't coerce to a hash recurcively" do
      properties = Class.new(Dry::Struct) do
        attribute :age, Dry::Types['strict.integer'].constructor(-> v { v + 1 })
      end

      struct = Class.new(Dry::Struct) do
        attribute :name, Dry::Types['strict.string']
        attribute :properties, properties
      end

      original = struct.new(name: 'Jane', properties: { age: 20 })

      expect(original.properties.age).to eql(21)

      transformed = original.new(name: 'John')

      expect(transformed.properties.age).to eql(21)
    end
  end

  describe '.call' do
    def construct_user(attributes)
      user_type.call(attributes)
    end

    it_behaves_like 'typical constructor'

    it 'returns itself when an argument is an instance of subclass' do
      user = root_type[
        name: :Jane, age: '21', root: true, address: { city: 'NYC', zipcode: 123 }
      ]

      expect(construct_user(user)).to be_equal(user)
    end
  end

  it 'defines .[] alias' do
    expect(described_class.method(:[])).to eq described_class.method(:call)
  end

  describe '.attribute' do
    def assert_valid_struct(user)
      expect(user.name).to eql('Jane')
      expect(user.age).to be(21)
      expect(user.address.city).to eql('NYC')
      expect(user.address.zipcode).to eql('123')
    end

    context 'when given a pre-defined nested type' do
      it 'defines attributes for the constructor' do
        user = user_type[
          name: :Jane, age: '21', address: { city: 'NYC', zipcode: 123 }
        ]

        assert_valid_struct(user)
      end
    end

    context 'when given a block-style nested type' do
      context 'when the nested type is not already defined' do
        context 'with no superclass type' do
          let(:user_type) do
            Class.new(Dry::Struct) do
              attribute :name, 'coercible.string'
              attribute :age, 'coercible.integer'
              attribute :address do
                attribute :city, 'strict.string'
                attribute :zipcode, 'coercible.string'
              end
            end
          end

          it 'defines attributes for the constructor' do
            user = user_type[
              name: :Jane, age: '21', address: { city: 'NYC', zipcode: 123 }
            ]

            assert_valid_struct(user)
          end

          it 'defines a nested type' do
            expect { user_type.const_get('Address') }.to_not raise_error
          end
        end

        context 'with a superclass type' do
          let(:user_type) do
            Class.new(Dry::Struct) do
              attribute :name, 'coercible.string'
              attribute :age, 'coercible.integer'
              attribute :address, Test::BaseAddress do
                attribute :city, 'strict.string'
                attribute :zipcode, 'coercible.string'
              end
            end
          end

          it 'defines attributes for the constructor' do
            user = user_type[
              name: :Jane, age: '21', address: {
                street: '123 Fake Street',
                city: 'NYC',
                zipcode: 123
              }
            ]

            assert_valid_struct(user)
            expect(user.address.street).to eq('123 Fake Street')
          end

          it 'defines a nested type' do
            expect { user_type.const_get('Address') }.to_not raise_error
          end
        end
      end

      context 'when the nested type is not already defined' do
        before do
          module Test
            module AlreadyDefined
              class User < Dry::Struct
                class Address
                end
              end
            end
          end
        end

        it 'raises a Dry::Struct::Error' do
          expect {
            Test::AlreadyDefined::User.attribute(:address) {}
          }.to raise_error(Dry::Struct::Error)
        end
      end
    end

    it 'ignores unknown keys' do
      user = user_type[
        name: :Jane, age: '21', address: { city: 'NYC', zipcode: 123 }, invalid: 'foo'
      ]

      assert_valid_struct(user)
    end

    it 'merges attributes from the parent struct' do
      user = root_type[
        name: :Jane, age: '21', root: true, address: { city: 'NYC', zipcode: 123 }
      ]

      assert_valid_struct(user)

      expect(user.root).to be(true)
    end

    context 'when no nested attribute block given' do
      it 'raises error when type is missing' do
        expect {
          class Test::Foo < Dry::Struct
            attribute :bar
          end
        }.to raise_error(ArgumentError)
      end
    end

    context 'when nested attribute block given' do
      it 'does not raise error when type is missing' do
        expect {
          class Test::Foo < Dry::Struct
            attribute :bar do
              attribute :foo, 'strict.string'
            end
          end
        }.to_not raise_error
      end
    end

    it 'raises error when attribute is defined twice' do
      expect {
        class Test::Foo < Dry::Struct
          attribute :bar, 'strict.string'
          attribute :bar, 'strict.string'
        end
      }.to raise_error(
        Dry::Struct::RepeatedAttributeError,
        'Attribute :bar has already been defined'
      )
    end

    it 'allows to redefine attributes in a subclass' do
      expect {
        class Test::Foo < Dry::Struct
          attribute :bar, 'strict.string'
        end

        class Test::Bar < Test::Foo
          attribute :bar, 'strict.integer'
        end
      }.not_to raise_error
    end

    it 'can be chained' do
      class Test::Foo < Dry::Struct
      end

      Test::Foo
        .attribute(:foo, 'strict.string')
        .attribute(:bar, 'strict.integer')

      foo = Test::Foo.new(foo: 'foo', bar: 123)

      expect(foo.foo).to eql('foo')
      expect(foo.bar).to eql(123)
    end

    it "doesn't define readers if methods are present" do
      class Test::Foo < Dry::Struct
        def age
          "#{ @attributes[:age] } years old"
        end
      end

      Test::Foo
        .attribute(:age, 'strict.integer')

      struct = Test::Foo.new(age: 18)
      expect(struct.age).to eql("18 years old")
    end
  end

  describe '.inherited' do
    it 'does not register Value' do
      expect { Dry::Struct.inherited(Dry::Struct::Value) }
        .to_not change(Dry::Types, :type_keys)
    end

    it 'adds attributes to all descendants' do
      Test::User.attribute(:signed_on, Dry::Types['strict.time'])

      expect(Test::SuperUser.schema).
        to include(signed_on: Dry::Types['strict.time'])
    end
  end

  describe 'when inheriting a struct from another struct' do
    it 'also inherits the schema' do
      class Test::Parent < Dry::Struct; input input.strict; end
      class Test::Child < Test::Parent; end
      expect(Test::Child.input).to be_strict
    end
  end

  describe 'with a blank schema' do
    it 'works for blank structs' do
      class Test::Foo < Dry::Struct; end
      expect(Test::Foo.new.to_h).to eql({})
    end
  end

  describe 'default values' do
    subject(:struct) do
      Class.new(Dry::Struct) do
        attribute :name, Dry::Types['strict.string'].default('Jane')
        attribute :age, Dry::Types['strict.integer']
        attribute :admin, Dry::Types['strict.bool'].default(true)
      end
    end

    it 'sets missing values using default-value types' do
      attrs = { name: 'Jane', age: 21, admin: true }

      expect(struct.new(name: 'Jane', age: 21).to_h).to eql(attrs)
      expect(struct.new(age: 21).to_h).to eql(attrs)
    end

    it 'raises error when values have incorrect types' do
      expect { struct.new(name: 'Jane', age: 21, admin: 'true') }.to raise_error(
        Dry::Struct::Error, %r["true" \(String\) has invalid type for :admin]
      )
    end
  end

  describe '#to_hash' do
    let(:parent_type) { Test::Parent }

    before do
      module Test
        class Parent < User
          attribute :children, Dry::Types['coercible.array'].member(Test::User)
        end
      end
    end

    it 'returns hash with attributes' do
      attributes  = {
        name: 'Jane',
        age:  29,
        address: { city: 'NYC', zipcode: '123' },
        children: [
          { name: 'Joe', age: 3, address: { city: 'NYC', zipcode: '123' } }
        ]
      }

      expect(parent_type[attributes].to_hash).to eql(attributes)
    end

    it "doesn't unwrap blindly anything mappable" do
      struct = Class.new(Dry::Struct) do
        attribute :mappable, Dry::Types['any']
      end

      mappable = Object.new.tap do |obj|
        def obj.map
          raise "not reached"
        end
      end

      value = struct.new(mappable: mappable)

      expect(value.to_h).to eql(mappable: mappable)
    end
  end

  describe 'unanonymous structs' do
    let(:struct) do
      Class.new(Dry::Struct) do
        def self.name
          'PersonName'
        end

        attribute :name, 'strict.string'
      end
    end

    before do
      struct_type = struct

      Test::Person = Class.new(Dry::Struct) do
        attribute :name, struct_type
      end
    end

    it 'works fine' do
      expect(struct.new(name: 'Jane')).to be_an_instance_of(struct)
      expect(Test::Person.new(name: { name: 'Jane' })).to be_an_instance_of(Test::Person)
    end
  end

  describe '#[]' do
    before do
      module Test
        class Task < Dry::Struct
          attribute :user, 'strict.string'
          undef user
        end
      end
    end

    it 'fetches raw attributes' do
      value = Test::Task[user: 'Jane']
      expect(value[:user]).to eql('Jane')
    end

    it 'raises a missing attribute error when no attribute exists' do
      value = Test::Task[user: 'Jane']

      expect { value[:name] }.
        to raise_error(Dry::Struct::MissingAttributeError).
             with_message("Missing attribute: :name")
    end

    describe 'protected methods' do
      before do
        class Test::Task
          attribute :hash, Dry::Types['strict.string']
          attribute :attributes, Dry::Types['array'].of(Dry::Types['strict.string'])
        end
      end

      it 'allows having attributes with reserved names' do
        value = Test::Task[user: 'Jane', hash: 'abc', attributes: %w(name)]

        expect(value.hash).to be_a(Integer)
        expect(value.attributes).
          to eql(user: 'Jane', hash: 'abc', attributes: %w(name))
        expect(value[:hash]).to eql('abc')
        expect(value[:attributes]).to eql(%w(name))
      end
    end
  end
end
