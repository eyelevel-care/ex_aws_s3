defmodule ExAws.S3 do
  @external_resource "README.md"
  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)

  import ExAws.S3.Utils
  alias ExAws.S3.Parsers

  @type acl_opt :: {:acl, canned_acl} | grant
  @type acl_opts :: [acl_opt]
  @type grant ::
          {:grant_read, grantee}
          | {:grant_read_acp, grantee}
          | {:grant_write_acp, grantee}
          | {:grant_full_control, grantee}
  @type canned_acl ::
          :private
          | :public_read
          | :public_read_write
          | :authenticated_read
          | :bucket_owner_read
          | :bucket_owner_full_control
  @type grantee :: [
          {:email, binary}
          | {:id, binary}
          | {:uri, binary}
        ]

  @type storage_class_opt :: {:storage_class, storage_class}
  @type storage_class ::
          :standard
          | :reduced_redundancy
          | :standard_ia
          | :onezone_ia
          | :intelligent_tiering
          | :glacier
          | :deep_archive
          | :outposts
          | :glacier_ir
          | :snow

  @type customer_encryption_opts :: [
          customer_algorithm: binary,
          customer_key: binary,
          customer_key_md5: binary
        ]
  @type encryption_opts ::
          binary
          | [aws_kms_key_id: binary]
          | customer_encryption_opts

  @type expires_in_seconds :: non_neg_integer

  @type presigned_url_opts :: [
          {:expires_in, expires_in_seconds}
          | {:virtual_host, boolean | binary}
          | {:s3_accelerate, boolean}
          | {:query_params, [{binary, binary}]}
          | {:headers, [{binary, binary}]}
          | {:bucket_as_host, boolean}
          | {:start_datetime, Calendar.naive_datetime() | :calendar.datetime()}
        ]

  @type presigned_post_opts :: [
          {:expires_in, expires_in_seconds}
          | {:acl, binary | {:starts_with, binary}}
          | {:content_length_range, [integer]}
          | {:key, binary | {:starts_with, binary}}
          | {:custom_conditions, [any()]}
          | {:virtual_host, boolean}
          | {:s3_accelerate, boolean}
          | {:bucket_as_host, boolean}
        ]

  @type presigned_post_result :: %{
          url: binary,
          fields: %{binary => binary}
        }

  @type amz_meta_opts :: [{atom, binary} | {binary, binary}, ...]

  @typedoc """
  The hashing algorithms that both S3 and Erlang support.

  https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html
  https://www.erlang.org/doc/man/crypto.html#type-hash_algorithm
  """
  @type hash_algorithm :: :sha | :sha256 | :md5

  ## Buckets
  #############
  @doc "List buckets"
  @spec list_buckets() :: ExAws.Operation.S3.t()
  @spec list_buckets(opts :: Keyword.t()) :: ExAws.Operation.S3.t()
  def list_buckets(opts \\ []) do
    request(:get, "", "/", [params: opts],
      parser: &ExAws.S3.Parsers.parse_all_my_buckets_result/1
    )
  end

  @doc "Delete a bucket"
  @spec delete_bucket(bucket :: binary) :: ExAws.Operation.S3.t()
  def delete_bucket(bucket) do
    request(:delete, bucket, "/")
  end

  @doc "Delete a bucket cors"
  @spec delete_bucket_cors(bucket :: binary) :: ExAws.Operation.S3.t()
  def delete_bucket_cors(bucket) do
    request(:delete, bucket, "/", resource: "cors")
  end

  @doc "Delete a bucket lifecycle"
  @spec delete_bucket_lifecycle(bucket :: binary) :: ExAws.Operation.S3.t()
  def delete_bucket_lifecycle(bucket) do
    request(:delete, bucket, "/", resource: "lifecycle")
  end

  @doc "Delete a bucket policy"
  @spec delete_bucket_policy(bucket :: binary) :: ExAws.Operation.S3.t()
  def delete_bucket_policy(bucket) do
    request(:delete, bucket, "/", resource: "policy")
  end

  @doc "Delete a bucket replication"
  @spec delete_bucket_replication(bucket :: binary) :: ExAws.Operation.S3.t()
  def delete_bucket_replication(bucket) do
    request(:delete, bucket, "/", resource: "replication")
  end

  @doc "Delete a bucket tagging"
  @spec delete_bucket_tagging(bucket :: binary) :: ExAws.Operation.S3.t()
  def delete_bucket_tagging(bucket) do
    request(:delete, bucket, "/", resource: "tagging")
  end

  @doc "Delete a bucket website"
  @spec delete_bucket_website(bucket :: binary) :: ExAws.Operation.S3.t()
  def delete_bucket_website(bucket) do
    request(:delete, bucket, "/", resource: "website")
  end

  @type list_objects_opts :: [
          {:delimiter, binary}
          | {:marker, binary}
          | {:prefix, binary}
          | {:encoding_type, binary}
          | {:max_keys, 0..1000}
          | {:stream_prefixes, boolean}
        ]

  @doc """
  List objects in bucket

  Can be streamed.

  ## Examples
  ```
  S3.list_objects("my-bucket") |> ExAws.request

  S3.list_objects("my-bucket") |> ExAws.stream!
  S3.list_objects("my-bucket", delimiter: "/", prefix: "backup") |> ExAws.stream!
  S3.list_objects("my-bucket", prefix: "some/inner/location/path") |> ExAws.stream!
  S3.list_objects("my-bucket", max_keys: 5, encoding_type: "url") |> ExAws.stream!
  ```
  """
  @spec list_objects(bucket :: binary) :: ExAws.Operation.S3.t()
  @spec list_objects(bucket :: binary, opts :: list_objects_opts) :: ExAws.Operation.S3.t()
  @params [:delimiter, :marker, :prefix, :encoding_type, :max_keys]
  def list_objects(bucket, opts \\ []) do
    params =
      opts
      |> format_and_take(@params)

    request(:get, bucket, "/", [params: params, headers: opts[:headers]],
      stream_builder: &ExAws.S3.Lazy.stream_objects!(bucket, opts, &1),
      parser: &ExAws.S3.Parsers.parse_list_objects/1
    )
  end

  @type list_objects_v2_opts :: [
          {:delimiter, binary}
          | {:prefix, binary}
          | {:encoding_type, binary}
          | {:max_keys, 0..1000}
          | {:stream_prefixes, boolean}
          | {:continuation_token, binary}
          | {:fetch_owner, boolean}
          | {:start_after, binary}
        ]

  @doc """
  List objects in bucket

  Can be streamed.

  ## Examples
  ```
  S3.list_objects_v2("my-bucket") |> ExAws.request

  S3.list_objects_v2("my-bucket") |> ExAws.stream!
  S3.list_objects_v2("my-bucket", delimiter: "/", prefix: "backup") |> ExAws.stream!
  S3.list_objects_v2("my-bucket", prefix: "some/inner/location/path") |> ExAws.stream!
  S3.list_objects_v2("my-bucket", max_keys: 5, encoding_type: "url") |> ExAws.stream!
  ```
  """
  @spec list_objects_v2(bucket :: binary) :: ExAws.Operation.S3.t()
  @spec list_objects_v2(bucket :: binary, opts :: list_objects_v2_opts) :: ExAws.Operation.S3.t()
  @params [
    :delimiter,
    :prefix,
    :encoding_type,
    :max_keys,
    :continuation_token,
    :fetch_owner,
    :start_after
  ]
  def list_objects_v2(bucket, opts \\ []) do
    params =
      opts
      |> format_and_take(@params)
      |> Map.put("list-type", 2)

    request(:get, bucket, "/", [params: params, headers: opts[:headers]],
      stream_builder: &ExAws.S3.Lazy.stream_objects_v2!(bucket, opts, &1),
      parser: &ExAws.S3.Parsers.parse_list_objects/1
    )
  end

  @doc "Get bucket acl"
  @spec get_bucket_acl(bucket :: binary) :: ExAws.Operation.S3.t()
  def get_bucket_acl(bucket) do
    request(:get, bucket, "/", resource: "acl")
  end

  @doc "Get bucket cors"
  @spec get_bucket_cors(bucket :: binary) :: ExAws.Operation.S3.t()
  def get_bucket_cors(bucket) do
    request(:get, bucket, "/", resource: "cors")
  end

  @doc "Get bucket lifecycle"
  @spec get_bucket_lifecycle(bucket :: binary) :: ExAws.Operation.S3.t()
  def get_bucket_lifecycle(bucket) do
    request(:get, bucket, "/", resource: "lifecycle")
  end

  @doc "Get bucket policy"
  @spec get_bucket_policy(bucket :: binary) :: ExAws.Operation.S3.t()
  def get_bucket_policy(bucket) do
    request(:get, bucket, "/", resource: "policy")
  end

  @doc "Get bucket location"
  @spec get_bucket_location(bucket :: binary) :: ExAws.Operation.S3.t()
  def get_bucket_location(bucket) do
    request(:get, bucket, "/", resource: "location")
  end

  @doc "Get bucket logging"
  @spec get_bucket_logging(bucket :: binary) :: ExAws.Operation.S3.t()
  def get_bucket_logging(bucket) do
    request(:get, bucket, "/", resource: "logging")
  end

  @doc "Get bucket notification"
  @spec get_bucket_notification(bucket :: binary) :: ExAws.Operation.S3.t()
  def get_bucket_notification(bucket) do
    request(:get, bucket, "/", resource: "notification")
  end

  @doc "Get bucket replication"
  @spec get_bucket_replication(bucket :: binary) :: ExAws.Operation.S3.t()
  def get_bucket_replication(bucket) do
    request(:get, bucket, "/", resource: "replication")
  end

  @doc "Get bucket tagging"
  @spec get_bucket_tagging(bucket :: binary) :: ExAws.Operation.S3.t()
  def get_bucket_tagging(bucket) do
    request(:get, bucket, "/", resource: "tagging")
  end

  @doc "Get bucket object versions"
  @spec get_bucket_object_versions(bucket :: binary) :: ExAws.Operation.S3.t()
  @spec get_bucket_object_versions(bucket :: binary, opts :: Keyword.t()) ::
          ExAws.Operation.S3.t()
  def get_bucket_object_versions(bucket, opts \\ []) do
    request(:get, bucket, "/", [resource: "versions", params: opts],
      parser: &ExAws.S3.Parsers.parse_bucket_object_versions/1
    )
  end

  @doc "Get bucket payment configuration"
  @spec get_bucket_request_payment(bucket :: binary) :: ExAws.Operation.S3.t()
  def get_bucket_request_payment(bucket) do
    request(:get, bucket, "/", resource: "requestPayment")
  end

  @doc "Get bucket versioning"
  @spec get_bucket_versioning(bucket :: binary) :: ExAws.Operation.S3.t()
  def get_bucket_versioning(bucket) do
    request(:get, bucket, "/", resource: "versioning")
  end

  @doc "Get bucket website"
  @spec get_bucket_website(bucket :: binary) :: ExAws.Operation.S3.t()
  def get_bucket_website(bucket) do
    request(:get, bucket, "/", resource: "website")
  end

  @doc "Determine if a bucket exists"
  @spec head_bucket(bucket :: binary) :: ExAws.Operation.S3.t()
  def head_bucket(bucket) do
    request(:head, bucket, "/")
  end

  @doc "List multipart uploads for a bucket"
  @spec list_multipart_uploads(bucket :: binary) :: ExAws.Operation.S3.t()
  @spec list_multipart_uploads(bucket :: binary, opts :: Keyword.t()) :: ExAws.Operation.S3.t()
  @params [:delimiter, :encoding_type, :max_uploads, :key_marker, :prefix, :upload_id_marker]
  def list_multipart_uploads(bucket, opts \\ []) do
    params = opts |> format_and_take(@params)

    request(:get, bucket, "/", [resource: "uploads", params: params], %{
      parser: &Parsers.parse_list_multipart_uploads/1
    })
  end

  @doc "Creates a bucket in the specified region"
  @spec put_bucket(bucket :: binary, region :: binary) :: ExAws.Operation.S3.t()
  def put_bucket(bucket, region, opts \\ [])
  def put_bucket(bucket, "", opts), do: put_bucket(bucket, "us-east-1", opts)

  def put_bucket(bucket, region, opts) do
    headers =
      opts
      |> Map.new()
      |> format_acl_headers

    body = region |> put_bucket_body

    request(:put, bucket, "/", body: body, headers: headers)
  end

  @doc "Update or create a bucket access control policy"
  @spec put_bucket_acl(bucket :: binary, opts :: acl_opts) :: ExAws.Operation.S3.t()
  def put_bucket_acl(bucket, grants) do
    request(:put, bucket, "/", headers: format_acl_headers(grants))
  end

  @doc "Update or create a bucket CORS policy"
  @spec put_bucket_cors(bucket :: binary, cors_config :: list(map())) :: ExAws.Operation.S3.t()
  def put_bucket_cors(bucket, cors_rules) do
    rules =
      cors_rules
      |> Enum.map(&build_cors_rule/1)
      |> IO.iodata_to_binary()

    body = "<CORSConfiguration>#{rules}</CORSConfiguration>"

    headers = calculate_content_header(body)

    request(:put, bucket, "/", resource: "cors", body: body, headers: headers)
  end

  @doc """
  Update or create a bucket lifecycle configuration

  ## Live-Cycle Rule Format

      %{
        # Unique id for the rule (max. 255 chars, max. 1000 rules allowed)
        id: "123",

        # Disabled rules are not executed
        enabled: true,

        # Filters
        # Can be based on prefix, object tag(s), both or none
        filter: %{
          prefix: "prefix/",
          tags: %{
            "key" => "value"
          }
        },

        # Actions
        # https://docs.aws.amazon.com/AmazonS3/latest/dev/intro-lifecycle-rules.html#intro-lifecycle-rules-actions
        actions: %{
          transition: %{
            trigger: {:date, ~D[2020-03-26]}, # Date or days based
            storage: ""
          },
          expiration: %{
            trigger: {:days, 2}, # Date or days based
            expired_object_delete_marker: true
          },
          noncurrent_version_transition: %{
            trigger: {:days, 2}, # Only days based
            storage: ""
          },
          noncurrent_version_expiration: %{
            trigger: {:days, 2} # Only days based
            newer_noncurrent_versions: 10
          },
          abort_incomplete_multipart_upload: %{
            trigger: {:days, 2} # Only days based
          }
        }
      }

  """
  @spec put_bucket_lifecycle(bucket :: binary, lifecycle_rules :: list(map())) ::
          ExAws.Operation.S3.t()
  def put_bucket_lifecycle(bucket, lifecycle_rules) do
    rules =
      lifecycle_rules
      |> Enum.map(&build_lifecycle_rule/1)
      |> IO.iodata_to_binary()

    body = "<LifecycleConfiguration>#{rules}</LifecycleConfiguration>"

    headers = calculate_content_header(body)

    request(:put, bucket, "/", resource: "lifecycle", body: body, headers: headers)
  end

  @doc "Update or create a bucket policy configuration"
  @spec put_bucket_policy(bucket :: binary, policy :: String.t()) :: ExAws.Operation.S3.t()
  def put_bucket_policy(bucket, policy) do
    request(:put, bucket, "/", resource: "policy", body: policy)
  end

  @doc "Update or create a bucket logging configuration"
  @spec put_bucket_logging(bucket :: binary, logging_config :: map()) :: no_return
  def put_bucket_logging(bucket, _logging_config) do
    raise "not yet implemented"
    request(:put, bucket, "/")
  end

  @doc "Update or create a bucket notification configuration"
  @spec put_bucket_notification(bucket :: binary, notification_config :: map()) :: no_return
  def put_bucket_notification(bucket, _notification_config) do
    raise "not yet implemented"
    request(:put, bucket, "/")
  end

  @doc "Update or create a bucket replication configuration"
  @spec put_bucket_replication(bucket :: binary, replication_config :: map()) :: no_return
  def put_bucket_replication(bucket, _replication_config) do
    raise "not yet implemented"
    request(:put, bucket, "/")
  end

  @doc "Update or create a bucket tagging configuration"
  @spec put_bucket_tagging(bucket :: binary, tags :: map()) :: no_return
  def put_bucket_tagging(bucket, _tags) do
    raise "not yet implemented"
    request(:put, bucket, "/")
  end

  @doc "Update or create a bucket requestPayment configuration"
  @spec put_bucket_request_payment(bucket :: binary, payer :: :requester | :bucket_owner) ::
          no_return
  def put_bucket_request_payment(bucket, _payer) do
    raise "not yet implemented"
    request(:put, bucket, "/")
  end

  @doc """
  Update or create a bucket versioning configuration

  ## Example
  ```
  ExAws.S3.put_bucket_versioning(
   "my-bucket",
   "<VersioningConfiguration><Status>Enabled</Status></VersioningConfiguration>"
  )
  |> ExAws.request()
  ```
  """
  @spec put_bucket_versioning(bucket :: binary, version_config :: binary) ::
          ExAws.Operation.S3.t()
  def put_bucket_versioning(bucket, version_config) do
    headers = calculate_content_header(version_config)
    request(:put, bucket, "/", resource: "versioning", body: version_config, headers: headers)
  end

  @doc "Update or create a bucket website configuration"
  @spec put_bucket_website(bucket :: binary, website_config :: binary) :: no_return
  def put_bucket_website(bucket, _website_config) do
    raise "not yet implemented"
    request(:put, bucket, "/")
  end

  ## Objects
  ###########

  @doc "Delete an object within a bucket"
  @type delete_object_opt ::
          {:x_amz_mfa, binary}
          | {:x_amz_request_payer, binary}
          | {:x_amz_bypass_governance_retention, binary}
          | {:x_amz_expected_bucket_owner, binary}
          | {:version_id, binary}
  @type delete_object_opts :: [delete_object_opt]
  @spec delete_object(bucket :: binary, object :: binary) :: ExAws.Operation.S3.t()
  @spec delete_object(bucket :: binary, object :: binary, opts :: delete_object_opts) ::
          ExAws.Operation.S3.t()
  @spec delete_object(bucket :: binary, object :: nil) :: no_return
  @request_headers [
    :x_amz_mfa,
    :x_amz_request_payer,
    :x_amz_bypass_governance_retention,
    :x_amz_expected_bucket_owner
  ]
  def delete_object(bucket, object, opts \\ [])

  def delete_object(_bucket, nil = _object, _opts) do
    raise "object must not be nil"
  end

  def delete_object(_bucket, "" = _object, _opts) do
    raise "object must not be empty string"
  end

  def delete_object(bucket, object, opts) do
    opts = opts |> Map.new()

    params =
      opts
      |> format_and_take([:version_id])

    headers =
      opts
      |> format_and_take(@request_headers)

    request(:delete, bucket, object, headers: headers, params: params)
  end

  @doc "Remove the entire tag set from the specified object"
  @spec delete_object_tagging(bucket :: binary, object :: binary, opts :: Keyword.t()) ::
          ExAws.Operation.S3.t()
  def delete_object_tagging(bucket, object, opts \\ []) do
    request(:delete, bucket, object, resource: "tagging", headers: opts |> Map.new())
  end

  @doc """
  Delete multiple objects within a bucket

  Limited to 1000 objects.
  """
  @spec delete_multiple_objects(
          bucket :: binary,
          objects :: [binary | {binary, binary}, ...]
        ) :: ExAws.Operation.S3.t()
  @spec delete_multiple_objects(
          bucket :: binary,
          objects :: [binary | {binary, binary}, ...],
          opts :: [quiet: true]
        ) :: ExAws.Operation.S3.t()
  def delete_multiple_objects(bucket, objects, opts \\ []) do
    objects_xml =
      Enum.map(objects, fn
        {key, version} ->
          [
            "<Object><Key>",
            escape_xml_string(key),
            "</Key><VersionId>",
            version,
            "</VersionId></Object>"
          ]

        key ->
          ["<Object><Key>", escape_xml_string(key), "</Key></Object>"]
      end)

    quiet =
      case opts do
        [quiet: true] -> "<Quiet>true</Quiet>"
        _ -> ""
      end

    body = [
      ~s(<?xml version="1.0" encoding="UTF-8"?>),
      "<Delete>",
      quiet,
      objects_xml,
      "</Delete>"
    ]

    body_binary = body |> IO.iodata_to_binary()

    request(:post, bucket, "/?delete",
      body: body_binary,
      headers: calculate_content_header(body_binary)
    )
  end

  @doc """
  Delete all listed objects.

  When performed, this function will continue making `delete_multiple_objects`
  requests deleting 1000 objects at a time until all are deleted.

  Can be streamed.

  ## Example
  ```
  stream = ExAws.S3.list_objects(bucket(), prefix: "some/prefix") |> ExAws.stream!() |> Stream.map(& &1.key)
  ExAws.S3.delete_all_objects(bucket(), stream) |> ExAws.request()
  ```
  """
  @spec delete_all_objects(
          bucket :: binary,
          objects :: [binary | {binary, binary}, ...] | Enumerable.t()
        ) :: ExAws.Operation.S3DeleteAllObjects.t()
  @spec delete_all_objects(
          bucket :: binary,
          objects :: [binary | {binary, binary}, ...] | Enumerable.t(),
          opts :: [quiet: true]
        ) :: ExAws.Operation.S3DeleteAllObjects.t()
  def delete_all_objects(bucket, objects, opts \\ []) do
    %ExAws.Operation.S3DeleteAllObjects{bucket: bucket, objects: objects, opts: opts}
  end

  @type get_object_response_opts :: [
          {:content_language, binary}
          | {:expires, binary}
          | {:cache_control, binary}
          | {:content_disposition, binary}
          | {:content_encoding, binary}
        ]
  @type get_object_opts :: [
          {:response, get_object_response_opts}
          | {:version_id, binary}
          | head_object_opt
        ]
  @doc """
  Get an object from a bucket

  ## Examples
  ```
  S3.get_object("my-bucket", "image.png")
  S3.get_object("my-bucket", "image.png", version_id: "ae57ekgXPpdiVZLkYVWoTAGRhGJ5swt9")
  ```
  """
  @spec get_object(bucket :: binary, object :: binary) :: ExAws.Operation.S3.t()
  @spec get_object(bucket :: binary, object :: binary, opts :: get_object_opts) ::
          ExAws.Operation.S3.t()
  @response_params [
    :content_type,
    :content_language,
    :expires,
    :cache_control,
    :content_disposition,
    :content_encoding
  ]
  @request_headers [:range, :if_modified_since, :if_unmodified_since, :if_match, :if_none_match]
  def get_object(bucket, object, opts \\ []) do
    opts = opts |> Map.new()

    response_opts =
      opts
      |> Map.get(:response, %{})
      |> format_and_take(@response_params)
      |> namespace("response")

    params =
      opts
      |> format_and_take([:version_id])
      |> Map.merge(response_opts)

    headers =
      opts
      |> format_and_take(@request_headers)

    headers =
      opts
      |> Map.get(:encryption, %{})
      |> build_encryption_headers
      |> Map.merge(headers)

    request(:get, bucket, object, headers: headers, params: params)
  end

  @type download_file_opts :: [
          max_concurrency: pos_integer,
          chunk_size: pos_integer,
          timeout: pos_integer
        ]

  @doc ~S"""
  Download an S3 object to a file.

  This operation downloads multiple parts of an S3 object concurrently, allowing
  you to maximize throughput.

  Defaults to a concurrency of 8, chunk size of 1MB, and a timeout of 1 minute.

  ### Streaming to memory

  In order to use `ExAws.stream!/2`, the third `dest` parameter must be set to `:memory`.
  An example would be like the following:

      ExAws.S3.download_file("example-bucket", "path/to/file.txt", :memory)
      |> ExAws.stream!()

  Note that **this won't start fetching anything immediately** since it returns an Elixir `Stream`.

  #### Streaming by line

  Streaming by line can be done with `Stream.chunk_while/4`. Here is an example:

      # Returns a stream which grabs chunks of data from S3 as specified in `opts`
      # but processes the stream line by line. For example, the default chunk
      # size of 1MB means requests for bytes from S3 will ask for 1MB sizes (to be downloaded)
      # however each element of the stream will be a single line.
      def generate_stream(bucket, file, opts \\ []) do
        bucket
        |> ExAws.S3.download_file(file, :memory, opts)
        |> ExAws.stream!()
        # Uncomment if you need to gunzip (and add dependency :stream_gzip)
        # |> StreamGzip.gunzip()
        |> Stream.chunk_while("", &chunk_fun/2, &to_line_stream_after_fun/1)
        |> Stream.concat()
      end

      def chunk_fun(chunk, acc) do
        to_try = acc <> chunk
        {elements, acc} = chunk_by_newline(to_try, "\n", [], {0, byte_size(to_try)})
        {:cont, elements, acc}
      end

      defp chunk_by_newline(_string, _newline, elements, {_offset, 0}) do
        {Enum.reverse(elements), ""}
      end

      defp chunk_by_newline(string, newline, elements, {offset, length}) do
        case :binary.match(string, newline, scope: {offset, length}) do
          {newline_offset, newline_length} ->
            difference = newline_length + newline_offset - offset
            element = binary_part(string, offset, difference)

            chunk_by_newline(
              string,
              newline,
              [element | elements],
              {newline_offset + newline_length, length - difference}
            )
          :nomatch ->
            {Enum.reverse(elements), binary_part(string, offset, length)}
        end
      end

      defp to_line_stream_after_fun(""), do: {:cont, []}
      defp to_line_stream_after_fun(acc), do: {:cont, [acc], []}
  """
  @spec download_file(bucket :: binary, path :: binary, dest :: :memory | binary) ::
          __MODULE__.Download.t()
  @spec download_file(
          bucket :: binary,
          path :: binary,
          dest :: :memory | binary,
          opts :: download_file_opts
        ) :: __MODULE__.Download.t()
  def download_file(bucket, path, dest, opts \\ []) do
    %__MODULE__.Download{
      bucket: bucket,
      path: path,
      dest: dest,
      opts: opts
    }
  end

  @type upload_opt ::
          {:max_concurrency, pos_integer}
          | {:timeout, pos_integer}
          | {:refetch_auth_on_request, boolean}
          | initiate_multipart_upload_opt
  @type upload_opts :: [upload_opt]

  @doc """
  Multipart upload to S3.

  Handles initialization, uploading parts concurrently, and multipart upload completion.

  ## Uploading a stream

  Streams that emit binaries may be uploaded directly to S3. Each binary will be uploaded
  as a chunk, so it must be at least 5 megabytes in size. The `S3.Upload.stream_file`
  helper takes care of reading the file in 5 megabyte chunks.
  ```
  "path/to/big/file"
  |> S3.Upload.stream_file
  |> S3.upload("my-bucket", "path/on/s3")
  |> ExAws.request! #=> :done
  ```

  ## Options

  These options are specific to this function
  * See `Task.async_stream/5`'s `:max_concurrency` and `:timeout` options.
    * `:max_concurrency` - only applies when uploading a stream. Sets the maximum number of tasks to run at the same time. Defaults to `4`
    * `:timeout` - the maximum amount of time (in milliseconds) each task is allowed to execute for. Defaults to `30_000`.
    * `:refetch_auth_on_request` - re-fetch the auth from the library config on each request in the upload process instead of using
      the initial auth. Fixes an edge case uploading large files when using a strategy from `ex_aws_sts` that provides short lived tokens,
      where uploads could fail if the token expires before the upload is completed. Defaults to `false`.

  All other options (ex. `:content_type`) are passed through to
  `ExAws.S3.initiate_multipart_upload/3`.

  """
  @spec upload(
          source :: Enumerable.t(),
          bucket :: String.t(),
          path :: String.t(),
          opts :: upload_opts
        ) :: __MODULE__.Upload.t()
  def upload(source, bucket, path, opts \\ []) do
    %__MODULE__.Upload{
      src: source,
      bucket: bucket,
      path: path,
      opts: opts
    }
  end

  @doc "Get an object's access control policy"
  @spec get_object_acl(bucket :: binary, object :: binary) :: ExAws.Operation.S3.t()
  @spec get_object_acl(bucket :: binary, object :: binary, opts :: Keyword.t()) ::
          ExAws.Operation.S3.t()
  def get_object_acl(bucket, object, opts \\ []) do
    request(:get, bucket, object, resource: "acl", headers: opts |> Map.new())
  end

  @doc "Get a torrent for a bucket"
  @spec get_object_torrent(bucket :: binary, object :: binary) :: ExAws.Operation.S3.t()
  def get_object_torrent(bucket, object) do
    request(:get, bucket, object, resource: "torrent")
  end

  @doc "Get object tagging"
  @spec get_object_tagging(bucket :: binary, object :: binary, opts :: Keyword.t()) ::
          ExAws.Operation.S3.t()
  def get_object_tagging(bucket, object, opts \\ []) do
    request(:get, bucket, object, [resource: "tagging", headers: opts |> Map.new()],
      parser: &ExAws.S3.Parsers.parse_object_tagging/1
    )
  end

  @type head_object_opt ::
          {:encryption, customer_encryption_opts}
          | {:range, binary}
          | {:version_id, binary}
          | {:if_modified_since, binary}
          | {:if_unmodified_since, binary}
          | {:if_match, binary}
          | {:if_none_match, binary}
  @type head_object_opts :: [head_object_opt]

  @doc "Determine if an object exists"
  @spec head_object(bucket :: binary, object :: binary) :: ExAws.Operation.S3.t()
  @spec head_object(bucket :: binary, object :: binary, opts :: head_object_opts) ::
          ExAws.Operation.S3.t()
  @request_headers [:range, :if_modified_since, :if_unmodified_since, :if_match, :if_none_match]
  def head_object(bucket, object, opts \\ []) do
    opts = opts |> Map.new()

    headers =
      opts
      |> format_and_take(@request_headers)

    headers =
      opts
      |> Map.get(:encryption, %{})
      |> build_encryption_headers
      |> Map.merge(headers)

    params = format_and_take(opts, [:version_id])
    request(:head, bucket, object, headers: headers, params: params)
  end

  @doc "Determine the CORS configuration for an object"
  @spec options_object(
          bucket :: binary,
          object :: binary,
          origin :: binary,
          request_method :: atom
        ) :: ExAws.Operation.S3.t()
  @spec options_object(
          bucket :: binary,
          object :: binary,
          origin :: binary,
          request_method :: atom,
          request_headers :: [binary]
        ) :: ExAws.Operation.S3.t()
  def options_object(bucket, object, origin, request_method, request_headers \\ []) do
    headers = [
      {"Origin", origin},
      {"Access-Control-Request-Method", request_method},
      {"Access-Control-Request-Headers", request_headers |> Enum.join(",")}
    ]

    request(:options, bucket, object, headers: headers)
  end

  @doc "Restore an object to a particular version"
  @spec post_object_restore(
          bucket :: binary,
          object :: binary,
          number_of_days :: pos_integer
        ) :: ExAws.Operation.S3.t()
  @spec post_object_restore(
          bucket :: binary,
          object :: binary,
          number_of_days :: pos_integer,
          opts :: [version_id: binary]
        ) :: ExAws.Operation.S3.t()
  def post_object_restore(bucket, object, number_of_days, opts \\ []) do
    params = format_and_take(opts, [:version_id])

    body = """
    <RestoreRequest xmlns="http://s3.amazonaws.com/doc/2006-3-01">
      <Days>#{number_of_days}</Days>
    </RestoreRequest>
    """

    request(:post, bucket, object, resource: "restore", params: params, body: body)
  end

  @type put_object_opts :: [
          {:cache_control, binary}
          | {:content_disposition, binary}
          | {:content_encoding, binary}
          | {:content_length, binary}
          | {:content_type, binary}
          | {:expect, binary}
          | {:expires, binary}
          | {:website_redirect_location, binary}
          | {:encryption, encryption_opts}
          | {:meta, amz_meta_opts}
          | {:if_match, binary}
          | {:if_none_match, binary}
          | acl_opt
          | storage_class_opt
        ]
  @doc "Create an object within a bucket"
  @spec put_object(bucket :: binary, object :: binary, body :: binary) :: ExAws.Operation.S3.t()
  @spec put_object(bucket :: binary, object :: binary, body :: binary, opts :: put_object_opts) ::
          ExAws.Operation.S3.t()
  def put_object(bucket, object, body, opts \\ []) do
    request(:put, bucket, object, body: body, headers: put_object_headers(opts))
  end

  @doc "Create or update an object's access control policy"
  @spec put_object_acl(bucket :: binary, object :: binary, acl :: acl_opts) ::
          ExAws.Operation.S3.t()
  def put_object_acl(bucket, object, acl) do
    headers = acl |> Map.new() |> format_acl_headers
    request(:put, bucket, object, headers: headers, resource: "acl")
  end

  @doc """
  Add a set of tags to an existing object

  ## Options

  - `:version_id` - The versionId of the object that the tag-set will be added to.

  """
  @spec put_object_tagging(
          bucket :: binary,
          object :: binary,
          tags :: Access.t(),
          opts :: Keyword.t()
        ) :: ExAws.Operation.S3.t()
  def put_object_tagging(bucket, object, tags, opts \\ []) do
    {version_id, opts} = Keyword.pop(opts, :version_id)

    params =
      if version_id do
        %{"versionId" => version_id}
      else
        %{}
      end

    tags_xml =
      Enum.map(tags, fn
        {key, value} ->
          ["<Tag><Key>", to_string(key), "</Key><Value>", to_string(value), "</Value></Tag>"]
      end)

    body = [
      ~s(<?xml version="1.0" encoding="UTF-8"?>),
      "<Tagging>",
      "<TagSet>",
      tags_xml,
      "</TagSet>",
      "</Tagging>"
    ]

    {ct, content_hash} = calculate_content_hash(body)

    headers =
      opts
      |> Map.new()
      |> Map.merge(%{ct => content_hash})

    body_binary = body |> IO.iodata_to_binary()

    request(:put, bucket, object,
      resource: "tagging",
      body: body_binary,
      headers: headers,
      params: params
    )
  end

  @spec calculate_content_header(iodata()) :: map()
  def calculate_content_header(content),
    do: calculate_content_hash(content) |> pair_tuple_to_map()

  @spec calculate_content_hash(iodata()) :: {binary(), binary()}
  defp calculate_content_hash(content) do
    alg = get_hash_config()
    {hash_header(alg), :crypto.hash(alg, content) |> Base.encode64()}
  end

  @spec get_hash_config() :: hash_algorithm()
  defp get_hash_config() do
    Application.get_env(:ex_aws_s3, :content_hash_algorithm) || :md5
  end

  # Supported erlang hash algorithms:
  # https://www.erlang.org/doc/man/crypto.html#type-hash_algorithm
  @spec hash_header(hash_algorithm()) :: binary()
  defp hash_header(:md5), do: "content-md5"
  defp hash_header(:sha), do: "x-amz-checksum-sha1"
  defp hash_header(alg) when is_atom(alg), do: "x-amz-checksum-#{to_string(alg)}"

  @spec pair_tuple_to_map({term(), term()}) :: map()
  defp pair_tuple_to_map(tuple), do: Map.new([tuple])

  @type put_object_copy_opts :: [
          {:metadata_directive, :COPY | :REPLACE}
          | {:copy_source_if_modified_since, binary}
          | {:copy_source_if_unmodified_since, binary}
          | {:copy_source_if_match, binary}
          | {:copy_source_if_none_match, binary}
          | {:website_redirect_location, binary}
          | {:destination_encryption, encryption_opts}
          | {:source_encryption, customer_encryption_opts}
          | {:cache_control, binary}
          | {:content_disposition, binary}
          | {:content_encoding, binary}
          | {:content_length, binary}
          | {:content_type, binary}
          | {:expect, binary}
          | {:expires, binary}
          | {:website_redirect_location, binary}
          | {:meta, amz_meta_opts}
          | acl_opt
          | storage_class_opt
        ]

  @doc "Copy an object"
  @spec put_object_copy(
          dest_bucket :: binary,
          dest_object :: binary,
          src_bucket :: binary,
          src_object :: binary
        ) :: ExAws.Operation.S3.t()
  @spec put_object_copy(
          dest_bucket :: binary,
          dest_object :: binary,
          src_bucket :: binary,
          src_object :: binary,
          opts :: put_object_copy_opts
        ) :: ExAws.Operation.S3.t()
  @amz_headers ~w(
    metadata_directive
    copy_source_if_modified_since
    copy_source_if_unmodified_since
    copy_source_if_match
    copy_source_if_none_match
    storage_class
    website_redirect_location)a
  def put_object_copy(dest_bucket, dest_object, src_bucket, src_object, opts \\ []) do
    opts = opts |> Map.new()

    amz_headers =
      opts
      |> format_and_take(@amz_headers)
      |> namespace("x-amz")

    source_encryption =
      opts
      |> Map.get(:source_encryption, %{})
      |> build_encryption_headers
      |> Enum.into(%{}, fn {<<"x-amz", k::binary>>, v} ->
        {"x-amz-copy-source" <> k, v}
      end)

    destination_encryption =
      opts
      |> Map.get(:destination_encryption, %{})
      |> build_encryption_headers

    regular_headers =
      opts
      |> Map.delete(:encryption)
      |> put_object_headers

    encoded_src_object =
      src_object
      |> String.split("/")
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn str -> URI.encode(str, &URI.char_unreserved?/1) end)
      |> Enum.join("/")

    headers =
      regular_headers
      |> Map.merge(amz_headers)
      |> Map.merge(source_encryption)
      |> Map.merge(destination_encryption)
      |> Map.put(
        "x-amz-copy-source",
        "/#{URI.encode(src_bucket, &URI.char_unreserved?/1)}/#{encoded_src_object}"
      )

    request(:put, dest_bucket, dest_object, headers: headers)
  end

  @type initiate_multipart_upload_opt ::
          {:cache_control, binary}
          | {:content_disposition, binary}
          | {:content_encoding, binary}
          | {:content_type, binary}
          | {:expires, binary}
          | {:website_redirect_location, binary}
          | {:encryption, encryption_opts}
          | {:meta, amz_meta_opts}
          | acl_opt
          | storage_class_opt
  @type initiate_multipart_upload_opts :: [initiate_multipart_upload_opt]

  @doc "Initiate a multipart upload"
  @spec initiate_multipart_upload(bucket :: binary, object :: binary) :: ExAws.Operation.S3.t()
  @spec initiate_multipart_upload(
          bucket :: binary,
          object :: binary,
          opts :: initiate_multipart_upload_opts
        ) :: ExAws.Operation.S3.t()
  def initiate_multipart_upload(bucket, object, opts \\ []) do
    request(:post, bucket, object, [resource: "uploads", headers: put_object_headers(opts)], %{
      parser: &Parsers.parse_initiate_multipart_upload/1
    })
  end

  @doc "Upload a part for a multipart upload"
  @spec upload_part(
          bucket :: binary,
          object :: binary,
          upload_id :: binary,
          part_number :: pos_integer,
          body :: binary
        ) :: ExAws.Operation.S3.t()
  @spec upload_part(
          bucket :: binary,
          object :: binary,
          upload_id :: binary,
          part_number :: pos_integer,
          body :: binary,
          opts :: [encryption_opts | {:expect, binary}]
        ) :: ExAws.Operation.S3.t()
  def upload_part(bucket, object, upload_id, part_number, body, _opts \\ []) do
    params = %{"uploadId" => upload_id, "partNumber" => part_number}
    request(:put, bucket, object, params: params, body: body)
  end

  @type upload_part_copy_opts :: [
          {:copy_source_if_modified_since, binary}
          | {:copy_source_if_unmodified_since, binary}
          | {:copy_source_if_match, binary}
          | {:copy_source_if_none_match, binary}
          | {:destination_encryption, encryption_opts}
          | {:source_encryption, customer_encryption_opts}
        ]

  @doc "Upload a part for a multipart copy"
  @spec upload_part_copy(
          dest_bucket :: binary,
          dest_object :: binary,
          src_bucket :: binary,
          src_object :: binary,
          upload_id :: binary,
          part_number :: pos_integer,
          source_range :: Range.t()
        ) :: ExAws.Operation.S3.t()
  @spec upload_part_copy(
          dest_bucket :: binary,
          dest_object :: binary,
          src_bucket :: binary,
          src_object :: binary,
          upload_id :: binary,
          part_number :: pos_integer,
          source_range :: Range.t(),
          opts :: upload_part_copy_opts
        ) :: ExAws.Operation.S3.t()
  @amz_headers ~w(
    copy_source_if_modified_since
    copy_source_if_unmodified_since
    copy_source_if_match
    copy_source_if_none_match)a
  def upload_part_copy(
        dest_bucket,
        dest_object,
        src_bucket,
        src_object,
        upload_id,
        part_number,
        source_range,
        opts \\ []
      ) do
    opts = opts |> Map.new()

    source_encryption =
      opts
      |> Map.get(:source_encryption, %{})
      |> build_encryption_headers
      |> Enum.into(%{}, fn {<<"x-amz", k::binary>>, v} ->
        {"x-amz-copy-source" <> k, v}
      end)

    destination_encryption =
      opts
      |> Map.get(:destination_encryption, %{})
      |> build_encryption_headers

    headers =
      opts
      |> format_and_take(@amz_headers)
      |> namespace("x-amz")
      |> Map.merge(source_encryption)
      |> Map.merge(destination_encryption)

    first..last//_ = source_range

    headers =
      headers
      |> Map.put("x-amz-copy-source-range", "bytes=#{first}-#{last}")
      |> Map.put("x-amz-copy-source", "/#{src_bucket}/#{src_object}")

    params = %{"uploadId" => upload_id, "partNumber" => part_number}

    request(:put, dest_bucket, dest_object, [headers: headers, params: params], %{
      parser: &Parsers.parse_upload_part_copy/1
    })
  end

  @doc "Complete a multipart upload"
  @spec complete_multipart_upload(
          bucket :: binary,
          object :: binary,
          upload_id :: binary,
          parts :: [{binary | pos_integer, binary}, ...]
        ) :: ExAws.Operation.S3.t()
  def complete_multipart_upload(bucket, object, upload_id, parts) do
    parts_xml =
      parts
      |> Enum.map(fn {part_number, etag} ->
        [
          "<Part>",
          "<PartNumber>",
          Integer.to_string(part_number),
          "</PartNumber>",
          "<ETag>",
          etag,
          "</ETag>",
          "</Part>"
        ]
      end)

    body =
      ["<CompleteMultipartUpload>", parts_xml, "</CompleteMultipartUpload>"]
      |> IO.iodata_to_binary()

    request(:post, bucket, object, [params: %{"uploadId" => upload_id}, body: body], %{
      parser: &Parsers.parse_complete_multipart_upload/1
    })
  end

  @doc "Abort a multipart upload"
  @spec abort_multipart_upload(bucket :: binary, object :: binary, upload_id :: binary) ::
          ExAws.Operation.S3.t()
  def abort_multipart_upload(bucket, object, upload_id) do
    request(:delete, bucket, object, params: %{"uploadId" => upload_id})
  end

  @doc "List the parts of a multipart upload"
  @spec list_parts(bucket :: binary, object :: binary, upload_id :: binary) ::
          ExAws.Operation.S3.t()
  @spec list_parts(bucket :: binary, object :: binary, upload_id :: binary, opts :: Keyword.t()) ::
          ExAws.Operation.S3.t()
  def list_parts(bucket, object, upload_id, opts \\ []) do
    params =
      opts
      |> Map.new()
      |> Map.merge(%{"uploadId" => upload_id})

    request(:get, bucket, object, [params: params], %{parser: &Parsers.parse_list_parts/1})
  end

  @doc """
  Generate a pre-signed URL for an object.
  This is a local operation and does not check whether the bucket or object exists.

  When option param `:virtual_host` is `true`, the bucket name will be used in
  the hostname, along with the s3 default host which will look like -
  `<bucket>.s3.<region>.amazonaws.com` host.

  When option param `:s3_accelerate` is `true`, the bucket name will be used as
  the hostname, along with the `s3-accelerate.amazonaws.com` host.

  When option param `:bucket_as_host` is `true`, the bucket name will be used as the full hostname.
  In this case, bucket must be set to a full hostname, for example `mybucket.example.com`.
  The `bucket_as_host` must be passed along with `virtual_host=true`

  Option param `:start_datetime` can be used to modify the start date for the presigned url, which
  allows for cache friendly urls.

  Additional (signed) query parameters can be added to the url by setting option param
  `:query_params` to a list of `{"key", "value"}` pairs. Useful if you are uploading parts of
  a multipart upload directly from the browser.

  Signed headers can be added to the url by setting option param `:headers` to
  a list of `{"key", "value"}` pairs.

  ## Example
  ```
  :s3
  |> ExAws.Config.new([])
  |> ExAws.S3.presigned_url(:get, "my-bucket", "my-object", [])
  ```
  """
  @spec presigned_url(
          config :: map,
          http_method :: atom,
          bucket :: binary,
          object :: binary,
          opts :: presigned_url_opts
        ) :: {:ok, binary} | {:error, binary}
  @one_week 60 * 60 * 24 * 7
  def presigned_url(config, http_method, bucket, object, opts \\ []) do
    expires_in = Keyword.get(opts, :expires_in, 3600)
    query_params = Keyword.get(opts, :query_params, [])
    virtual_host = Keyword.get(opts, :virtual_host, false)
    s3_accelerate = Keyword.get(opts, :s3_accelerate, false)
    bucket_as_host = Keyword.get(opts, :bucket_as_host, false)
    headers = Keyword.get(opts, :headers, [])

    {config, virtual_host} =
      if s3_accelerate,
        do: {put_accelerate_host(config), true},
        else: {config, virtual_host}

    case expires_in > @one_week do
      true ->
        {:error, "expires_in_exceeds_one_week"}

      false ->
        url = url_to_sign(bucket, object, config, virtual_host, bucket_as_host)

        datetime =
          Keyword.get(opts, :start_datetime, NaiveDateTime.utc_now())
          |> case do
            dt when is_struct(dt, DateTime) or is_struct(dt, NaiveDateTime) ->
              NaiveDateTime.to_erl(dt)

            # assume :calendar.datetime()
            dt ->
              dt
          end

        ExAws.Auth.presigned_url(
          http_method,
          url,
          :s3,
          datetime,
          config,
          expires_in,
          query_params,
          nil,
          headers
        )
    end
  end

  @doc """
  Generate a pre-signed post for an object.

  When option param `:virtual_host` is `true`, the bucket name will be used in
  the hostname, along with the s3 default host which will look like -
  `<bucket>.s3.<region>.amazonaws.com` host.

  When option param `:s3_accelerate` is `true`, the bucket name will be used as
  the hostname, along with the `s3-accelerate.amazonaws.com` host.

  When option param `:bucket_as_host` is `true`, the bucket name will be used as the full hostname.
  In this case, bucket must be set to a full hostname, for example `mybucket.example.com`.
  The `bucket_as_host` must be passed along with `virtual_host=true`
  """
  @spec presigned_post(
          config :: map,
          bucket :: binary,
          key :: binary | nil,
          opts :: presigned_post_opts()
        ) :: presigned_post_result()
  def presigned_post(config, bucket, key, opts \\ []) do
    expires_in = Keyword.get(opts, :expires_in, 3600)
    virtual_host = Keyword.get(opts, :virtual_host, false)
    s3_accelerate = Keyword.get(opts, :s3_accelerate, false)
    bucket_as_host = Keyword.get(opts, :bucket_as_host, false)
    {:ok, datetime} = DateTime.now("Etc/UTC")
    expiration_date = DateTime.add(datetime, expires_in, :second)
    datetime = datetime_to_erlang_time(datetime)

    credential = ExAws.Auth.Credentials.generate_credential_v4("s3", config, datetime)

    {config, virtual_host} =
      if s3_accelerate,
        do: {put_accelerate_host(config), true},
        else: {config, virtual_host}

    # security_token will be present when temporary credentials are used
    {opts, security_token_fields} =
      if config[:security_token] do
        security_token_config = [%{"X-Amz-Security-Token" => config[:security_token]}]

        {
          Keyword.update(
            opts,
            :custom_conditions,
            security_token_config,
            &(&1 ++ security_token_config)
          ),
          %{"X-Amz-Security-Token" => config[:security_token]}
        }
      else
        {opts, %{}}
      end

    policy =
      build_amz_post_policy(datetime, expiration_date, bucket, credential, opts, key)
      |> config.json_codec.encode!()
      |> Base.encode64()

    signature = ExAws.Auth.Signatures.generate_signature_v4("s3", config, datetime, policy)

    %{
      url: url_to_sign(bucket, nil, config, virtual_host, bucket_as_host),
      fields:
        %{
          "key" => key,
          "X-Amz-Algorithm" => "AWS4-HMAC-SHA256",
          "X-Amz-Credential" => credential,
          "X-Amz-Date" => ExAws.Auth.Utils.amz_date(datetime),
          "Policy" => policy,
          "X-Amz-Signature" => signature
        }
        |> Map.merge(security_token_fields)
    }
  end

  defp put_bucket_body("us-east-1"), do: ""

  defp put_bucket_body(region) do
    """
    <CreateBucketConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
      <LocationConstraint>#{region}</LocationConstraint>
    </CreateBucketConfiguration>
    """
  end

  defp url_to_sign(bucket, object, config, virtual_host, bucket_as_host) do
    port = sanitized_port_component(config)

    object =
      if object do
        ensure_slash(object)
      else
        ""
      end

    case virtual_host do
      true ->
        case bucket_as_host do
          true -> "#{config[:scheme]}#{bucket}#{port}#{object}"
          false -> "#{config[:scheme]}#{bucket}.#{config[:host]}#{port}#{object}"
        end

      false ->
        "#{config[:scheme]}#{config[:host]}#{port}/#{bucket}#{object}"

      defined_virtual_host ->
        "#{defined_virtual_host}/#{bucket}#{object}"
    end
  end

  defp request(http_method, bucket, path, data \\ [], opts \\ %{}) do
    %ExAws.Operation.S3{
      http_method: http_method,
      bucket: bucket,
      path: path,
      body: data[:body] || "",
      headers: data[:headers] || %{},
      resource: data[:resource] || "",
      params: data[:params] || %{}
    }
    |> struct(opts)
  end

  defp put_accelerate_host(config) do
    Map.put(config, :host, "s3-accelerate.amazonaws.com")
  end

  defp escape_xml_string(value) do
    String.replace(value, ["'", "\"", "&", "<", ">", "\r", "\n"], fn
      "'" -> "&apos;"
      "\"" -> "&quot;"
      "&" -> "&amp;"
      "<" -> "&lt;"
      ">" -> "&gt;"
      "\r" -> "&#13;"
      "\n" -> "&#10;"
    end)
  end
end
