% dj.internal.File - an external storage class for local file stores.
classdef File
    properties (Hidden, Constant)
        validation_config = struct( ...
            'store_config', struct( ...
                'protocol', struct( ...
                    'required', true, ...
                    'type_check', @(x) ischar(x) ...
                ), ...
                'location', struct( ...
                    'required', true, ...
                    'type_check', @(x) ischar(x) ...
                ) ...
            ), ...
            'type_config', struct( ...
                'blob', struct( ...
                    'subfolding', struct( ...
                        'required', false, ...
                        'type_check', @(x) all(floor(x) == x), ...
                        'default', [2, 2] ...
                    ), ...
                    'cache', struct( ...
                        'required', false, ...
                        'type_check', @(x) ischar(x), ...
                        'default', [] ...
                    ) ...
                ) ...
            ) ...
        )
    end
    properties
        protocol
        location
        blob_config
    end
    methods (Static)
        function result = exists(external_filepath)
            result = isfile(external_filepath);
        end
        function remove_object(external_filepath)
            delete(external_filepath);
        end
        function upload_buffer(buffer, external_filepath)
            fileID = fopen(external_filepath, 'w');
            fwrite(fileID, buffer);
            fclose(fileID);
        end
        function result = download_buffer(external_filepath)
            fileID = fopen(external_filepath, 'r');
            result = fread(fileID);
        end
    end
    methods
        function self = File(config)
            self.protocol = config.store_config.protocol;
            self.location = config.store_config.location;
            self.blob_config = config.type_config.blob;
        end
        function external_filepath = make_external_filepath(self, relative_filepath)
            external_filepath = [self.location '/' relative_filepath];
        end
    end
end


%x make_external_filepath -- (validation) (for file use filesystem style
% directly, for s3 convert to posix path)

%x upload_file -- (for uploading filepath, attach)
%x download_file -- (for downloading filepath, attach)
%x upload_buffer -- (for uploading blob)
%x download_buffer -- (for downloading blob)
%x remove_object -- (for deleting object from storage)
%x exists -- (verify if object exists in storage)



