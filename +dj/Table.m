% dj.Table provides the data definition interface to a single table in the
% database.
%
% Initialization:
%    table = dj.Table('package.ClassName')
%
% If the table does not exist, it is created based on the definition
% specified in the first percent-brace comment block in the file whose path
% is returned by which('package.ClassName'), which will normally contain the
% class definition of the derived class that works with this table.
%
% The file +package/ClassName.m need not exist if the table already exists
% in the database. Only if the table does not exist will dj.Table access
% the table definition file and create the table in the database.
%
% The syntax of the table definition can be found at
% http://code.google.com/p/datajoint/wiki/TableDeclarationSyntax

% -- Dimitri Yatsenko, 2009-2012.

classdef (Sealed) Table < handle
    
    properties(SetAccess = private)
        schema   % handle to a schema object
        className    % the name of the corresponding base dj.Relvar class
    end
    
    properties(Dependent, SetAccess = private)
        info     % name, tier, comment.  See dj.Schema
        header    % structure array describing header
        fullTableName  % table name with database, escaped in backquotes
        plainTableName  % just the table name
    end
    
    properties(Constant)
        mysql_constants = {'CURRENT_TIMESTAMP'}
    end
    
    properties(Access=private)
        declaration
    end
    
    
    methods
        function self = Table(className, declaration)
            % obj = dj.Table('package.className')
            self.className = className;
            assert(ischar(self.className),  ...
                'dj.Table requres input ''package.ClassName''')
            assert(~isempty(regexp(self.className,'^\w+\.[A-Z]\w+','once')), ...
                'invalid table identification ''%s''. Should be package.ClassName', ...
                self.className)
            if nargin>=2
                self.declaration = declaration;
            end
        end
        
        
        function ret = get.schema(self)
            if isempty(self.schema)
                schemaFunction = regexprep(self.className, '\.\w+$', '.getSchema');
                assert(~isempty(which(schemaFunction)), ['Not found: ' schemaFunction])
                self.schema = eval(schemaFunction);
                assert(isa(self.schema, 'dj.Schema'), ...
                    [schemaFunction ' must return an instance of dj.Schema'])
            end
            ret = self.schema;
        end
        
        
        function yes = exists(self)
            yes = any(strcmp(self.className, self.schema.classNames));
        end
        
        
        function info = get.info(self)
            if ~self.exists   % table does not exist. Create it.
                self.create
                assert(self.exists, 'Table %s is not found', self.className)
            end
            info = self.schema.tables(strcmp(self.className, self.schema.classNames));
        end
        
        
        function header = get.header(self)
            header = self.schema.header(strcmp(self.info.name, {self.schema.header.table}));
        end
        
        
        function name = get.fullTableName(self)
            if isempty(self.schema.prefix)
                name = sprintf('`%s`.`%s`', self.schema.dbname, self.info.name);
            else
                name = sprintf('`%s`.`%s/%s`', self.schema.dbname, self.schema.prefix, self.info.name);
            end
        end
        
        
        function name = get.plainTableName(self)
            % just the table name, no database and no backquotes
            if isempty(self.schema.prefix)
                name = self.info.name;
            else
                name = sprintf('%s/%s', self.schema.prefix, self.info.name);
            end
        end
        
        
        function display(self)
            display@handle(self)
            for i=1:numel(self)
                disp(self(i).re(true))
                fprintf \n
            end
        end
        
        
        function erd(self, depth1, depth2)
            % dj.Table/erd - plot the entity relationship diagram of tables
            % that are connected to self.
            %
            % SYNTAX
            %   table.erd([depth1[,depth2]])
            %
            % depth1 and depth2 specify the connectivity radius upstream
            % (depth<0) and downstream (depth>0) of this table.
            % Omitting both depths defaults to table.erd(-2,2).
            % Omitting any one of the depths sets it to zero.
            %
            % Examples:
            %   t = dj.Table('vis2p.Scans');
            %   t.erd       % plot two levels above and below
            %   t.erd( 2);  % plot dependents up to 2 levels below
            %   t.erd(-1);  % plot only immediate ancestors
            %
            % See also dj.Schema/erd
            if ~self.exists
                self.create
            end
            switch nargin
                case 1
                    depth1 = -2;
                    depth2 = +2;
                case 2
                    depth2 = max(0, depth1);
                    depth1 = min(0, depth1);
            end
            
            self.schema.erd(self.getNeighbors(depth1, depth2))
        end
        
        
        function str = re(self, expandForeignKeys)
            % dj.Table/re - "reverse engineer" the table declaration.
            %
            % SYNTAX:
            %   str = table.re
            %   str = table.re(true)
            %
            % str will contain the table declaration string that can be used
            % to create the table using dj.Table.
            %
            % When the second input expandForeignKeys is true, then references
            % to other tables are not displayed and foreign key header are shown
            % as regular header.
            %
            % See also dj.Table
            
            expandForeignKeys = nargin>=2 && expandForeignKeys;
            
            if expandForeignKeys
                str = '';
            else
                str = sprintf('%%{\n');
            end
            str = sprintf('%s%s (%s) # %s\n', ...
                str, self.className, self.info.tier, self.info.comment);
            assert(any(strcmp(self.schema.classNames, self.className)), ...
                'class %s does not appear in the class list of the schema', self.className);
            
            keyFields = {self.header([self.header.iskey]).name};
            
            if ~expandForeignKeys
                % list parent references
                for refClassName = self.schema.getParents(self.className, 1)
                    refObj = dj.Table(self.schema.conn.getPackage(refClassName{1}));
                    str = sprintf('%s\n-> %s',str, refObj.className);
                    excludeFields = {refObj.header([refObj.header.iskey]).name};
                    keyFields = keyFields(~ismember(keyFields, excludeFields));
                end
            end
            
            for i=find(ismember({self.header.name}, keyFields))
                comment = self.header(i).comment;
                str = sprintf('%s\n%-40s# %s', str, ...
                    sprintf('%-16s: %s', self.header(i).name, self.header(i).type), ...
                    comment);
            end
            
            % dividing line
            str = sprintf('%s\n---', str);
            
            dependentFields = {self.header(~[self.header.iskey]).name};
            
            % list other references
            if ~expandForeignKeys
                for refClassName = self.schema.getParents(self.className, 2)
                    refObj = dj.Table(self.schema.conn.getPackage(refClassName{1}));
                    str = sprintf('%s\n-> %s',str, refObj.className);
                    excludeFields = {refObj.header([refObj.header.iskey]).name};
                    dependentFields = dependentFields(~ismember(dependentFields, excludeFields));
                end
            end
            
            % list remaining header
            for i=find(ismember({self.header.name}, dependentFields))
                if self.header(i).isnullable
                    default = '=null';
                elseif strcmp(char(self.header(i).default(:)'), '<<<none>>>')
                    default = '';
                elseif self.header(i).isNumeric || ...
                        any(strcmp(self.header(i).default,self.mysql_constants))
                    default = ['=' self.header(i).default];
                else
                    default = ['="' self.header(i).default '"'];
                end
                comment = self.header(i).comment;
                str = sprintf('%s\n%-60s# %s', str, ...
                    sprintf('%-28s: %s', [self.header(i).name default], self.header(i).type), ...
                    comment);
            end
            str = sprintf('%s\n', str);
            
            if ~expandForeignKeys
                str = sprintf('%s%%}\n', str);
            end
        end
        
        
        function optimize(self)
            % optimizes the table if it has become fragmented after repeated inserts and deletes.
            % See http://dev.mysql.com/doc/refman/5.6/en/optimize-table.html
            fprintf 'optimizing ...'
            status = self.schema.conn.query(...
                sprintf('OPTIMIZE LOCAL TABLE %s', self.fullTableName));
            disp(status.Msg_text{end})
        end
        
        
        
        
        %%%%% ALTER METHODS: change table definitions %%%%%%%%%%%%
        function setTableComment(self, newComment)
            % dj.Table/setTableComment - update the table comment
            % in the table declaration
            self.alter(sprintf('COMMENT="%s"', newComment));
        end
        
        function addAttribute(self, definition)
            % dj.Table/addAttribute - add a new attribute to the
            % table. A full line from the table definition is
            % passed in as "definition".
            sql = fieldToSQL(parseAttrDef(definition, false));
            self.alter(sprintf('ADD COLUMN %s', sql(1:end-2)));
        end
        
        function dropAttribute(self, attrName)
            % dj.Table/dropAttribute - drop the attribute attrName
            % from the table definition
            self.alter(sprintf('DROP COLUMN `%s`', attrName));
        end
        
        function alterAttribute(self, attrName, newDefinition)
            % dj.Table/alterAttribute - Modify the definition of attribute
            % attrName using its new line from the table definition
            % "newDefinition"
            sql = fieldToSQL(parseAttrDef(newDefinition, false));
            self.alter(sprintf('CHANGE COLUMN `%s` %s', attrName, ...
                sql(1:end-2)));
        end
        
        function addForeignKey(self, target)
            % add a foreign key constraint.
            % The target must be a dj.Relvar object.
            % The referencing table must already possess all the attributes
            % of the primary key of the referenced table.
            %
            % EXAMPLE:
            %    tp.Align.table.addForeignKey(common.Scan)
            
            fieldList = sprintf('%s,', target.primaryKey{:});
            fieldList(end)=[];  % drop trailing comma
            self.alter( sprintf(...
                ['ADD FOREIGN KEY (%s) REFERENCES %s (%s) ' ...
                 'ON UPDATE CASCADE ON DELETE RESTRICT\n'], ...
                fieldList, target.fullTableName, fieldList));
        end
        
        function dropForeignKey(self, target)
            % drop a foreign key constraint.
            % The target must be a dj.Relvar object.
            
            % get constraint name
            sql = sprintf( ...
                ['SELECT distinct constraint_name AS name ' ...
                 'FROM information_schema.key_column_usage ' ...
                 'WHERE table_schema="%s" and table_name="%s"' ...
                 'AND referenced_table_schema="%s" ' ...
                 'AND referenced_table_name="%s"'], ...
                self.table.schema.dbname, self.plainTableName, ...
                target.table.schema.dbname, target.table.plainTableName);
            name = self.schema.conn.query(sql);
            if isempty(name.name)
                disp 'No matching foreign key'
            else
                self.alter(sprintf('DROP FOREIGN KEY %s', name.name{1}));
            end
        end
        
        function syncDef(self)
            % dj.Table/syncDef replace the table declaration in the file
            % <package>.<className>.m with the actual definition from the database.
            %
            % This method is useful if the table definition has been
            % changed by other means than the regular datajoint definition
            % process.
            
            path = which(self.className);
            if isempty(path)
                fprintf('File %s.m is not found\n', self.className);
            else
                s = input(sprintf('Update table declaration in %s? yes/no > ',path), 's');
                if ~strcmpi(s,'yes')
                    disp 'No? Table declaration left unpdated.'
                else
                    % read old file
                    f = fopen(path, 'rt');
                    lines = {};
                    line = fgetl(f);
                    while ischar(line)
                        lines{end+1} = line;  %#ok<AGROW>
                        line = fgetl(f);
                    end
                    fclose(f);
                    
                    % write new file
                    f = fopen(path, 'wt');
                    p1 = find(strcmp(strtrim(lines), '%{'), 1, 'first');
                    p2 = find(strcmp(strtrim(lines), '%}'), 1, 'first');
                    if isempty(p1)
                        p1 = 1;
                        p2 = 1;
                    end
                    for i=1:p1-1
                        fprintf(f,'%s\n',lines{i});
                    end
                    fprintf(f,'%s', self.re);
                    for i=p2+1:length(lines)
                        fprintf(f,'%s\n',lines{i});
                    end
                    fclose(f);
                    disp 'updated table definition'
                end
            end
        end
        
        function list = getEnumValues(self, attr)
            % returns the list of allowed values for the attribute attr of type enum
            ix = strcmpi(attr, {self.header.name});
            if ~any(ix)
                throwAsCaller(MException('DataJoint:invalidAttributeName', ...
                    'attribute "%s" not found', attr))
            end
            list = regexpi(self.header(ix).type,'^enum\((?<list>''.*'')\)$', 'names');
            if isempty(list)
                throwAsCaller(MException('DataJoint:invalidAttributeName', ...
                    'attribute "%s" not of type ENUM', attr))
            end
            list = regexp(list.list,'''(?<item>[^'']+)''','names');
            list = {list.item};
        end
        
        %%%%%  END ALTER METHODS
        
        
        
        function drop(self)
            % dj.Table/drop - drop the table and all its dependents.
            % Confirmation is requested if the dropped tables contain data.
            %
            % Although drop reloads the schema information upon completion,
            % "clear classes" may be necessary to remove constant object
            % properties and persistent variables that refer to the dropped
            % table.
            %
            % See also dj.Table, dj.BaseRelvar/del
            
            if ~self.exists
                disp 'Nothing to drop'
                return
            end
            
            self.schema.conn.cancelTransaction   % exit ongoing transaction
            % warn user if self is a subtable
            if ismember(self.info.tier, {'imported','computed'}) && ...
                    ~isempty(which(self.className))
                rel = eval(self.className);
                if ~isa(rel,'dj.AutoPopulate')
                    fprintf(['\n!!! %s is a subtable. For referential integrity, ' ...
                        'drop its parent table instead.\n'], self.className)
                    if ~strcmpi('yes', input('Proceed anyway? yes/no >','s'))
                        fprintf '\ndrop cancelled\n\n'
                        return
                    end
                end
            end
            
            % compile the list of dropped tables
            doDrop = true;
            fprintf 'ABOUT TO DROP TABLES: \n'
            names = {self.className};
            tables = self;
            new = self;
            n = count(init(dj.BaseRelvar, self));
            fprintf('%s %s: %d tuples\n', self.info.tier, self.info.name, n);
            doDrop = doDrop && ~n;   % drop without prompt if empty
                    
            while ~isempty(new)
                curr = new(1);
                new(1) = [];
                sch = curr.schema;
                ixCurr = strcmp(sch.classNames, curr.className);
                j = find(sch.dependencies(:,ixCurr));
                j = j(~ismember(sch.classNames(j),names));  % remove duplicates
                j = j(:)';
                children = sch.classNames(j);
                names = [names children]; %#ok<AGROW>
                for j=1:length(children)
                    child = sch.conn.getPackage(children{j},false);
                    if child(1) == '$'  % ignore unloaded schemas
                        throwAsCaller(MException('DataJoint:dropTable', ...
                            'cannot drop %s because its schema is not loaded', child))
                    else
                        table = dj.Table(child);
                        n = count(init(dj.BaseRelvar, table));
                        fprintf('%s %s: %d tuples\n', table.info.tier, table.info.name, n);
                        tables(end+1) = table; %#ok<AGROW>
                        new(end+1) = table; %#ok<AGROW>
                        doDrop = doDrop && ~n;   % drop without prompt if empty
                    end
                end
            end
            
            % if any table has data, give option to cancel
            if ~doDrop && ~strcmpi('yes', input('Proceed to drop? yes/no >', 's'));
                disp 'User cancelled table drop'
            else
                try
                    for table = tables(end:-1:1)
                        self.schema.conn.query(sprintf('DROP TABLE %s', table.fullTableName))
                        fprintf('Dropped table %s\n', table.fullTableName)
                    end
                catch err
                    self.schema.conn.reload
                    rethrow(err)
                end
                % reload all schemas
                self.schema.conn.reload
            end
            fprintf \n
        end
    end
    
    methods(Access=private)
        
        function neighbors = getNeighbors(self, depth1, depth2, crossSchemas)
            % dj.Table/getNeighbors -- get the class names of tables that are
            % directly related to the given table.
            %
            % depth1 and depth2 specify the connectivity radius upstream
            % (depth<0) and downstream (depth>0) of this table.
            % Omitting both depths defaults to (-2,2).
            % Omitting any one of the depths sets it to zero.
            %
            % If crossSchemas is set to true, the search cascades into other schemas.
            %
            % Examples:
            %   table.getNeighbors(-1,0)     % get table's parents
            %   table.getNeighbors(0,1)      % get table's children
            %   table.getNeighbors(-2,2)     % two levels up and down
            
            crossSchemas = nargin>=4 && crossSchemas;
            
            % find tables on which self depends
            neighbors = {self.className};
            nodes = {self.className};
            for j=1:-depth1
                nodes = unique(self.schema.getParents(nodes,[1 2],crossSchemas));
                if isempty(nodes)
                    break
                end
                neighbors(ismember(neighbors,nodes))=[];
                neighbors = [nodes neighbors];  %#ok:<AGROW>
            end
            
            % find tables dependent on self
            nodes = {self.className};
            for j=1:depth2
                nodes = unique(self.schema.getChildren(nodes,[1 2],crossSchemas));
                if isempty(nodes)
                    break;
                end
                neighbors(ismember(neighbors,nodes))=[];
                neighbors = [neighbors nodes];  %#ok:<AGROW>
            end
        end
        
        
        
        
        function declaration = getDeclaration(self)
            % extract the table declaration with the first percent-brace comment
            % block of the matching .m file.
            if ~isempty(self.declaration)
                declaration = self.declaration;
            else
                file = which(self.className);
                assert(~isempty(file), 'DataJoint:MissingTableDefnition', ...
                    'Could not find table definition file %s', file)
                declaration = readPercentBraceComment(file);
                assert(~isempty(declaration), 'DataJoint:MissingTableDefnition', ...
                    'Could not find the table declaration in %s', file)
            end
        end
        
        
        function create(self)
            [tableInfo, parents, references, fieldDefs, indexDefs] = ...
                parseDeclaration(self.getDeclaration);
            cname = sprintf('%s.%s', tableInfo.package, tableInfo.className);
            assert(strcmp(cname, self.className), ...
                'Table name %s does not match in file %s', cname, self.className)
            
            % compile the CREATE TABLE statement
            tableName = [...
                dj.Schema.tierPrefixes{strcmp(tableInfo.tier, dj.Schema.allowedTiers)}, ...
                dj.Schema.fromCamelCase(tableInfo.className)];
            if ~isempty(self.schema.prefix)
                tableName = sprintf('%s/%s', self.schema.prefix, tableName);
            end
            
            sql = sprintf('CREATE TABLE `%s`.`%s` (\n', self.schema.dbname, tableName);
            
            % add inherited primary key attributes
            primaryKeyFields = {};
            nonKeyFields = {};
            for iRef = 1:length(parents)
                for iField = find([parents{iRef}.table.header.iskey])
                    field = parents{iRef}.table.header(iField);
                    if ~ismember(field.name, primaryKeyFields)
                        primaryKeyFields{end+1} = field.name;   %#ok<AGROW>
                        assert(~field.isnullable, 'primary key header cannot be nullable')
                        sql = sprintf('%s%s', sql, fieldToSQL(field));
                    end
                end
            end
            
            % add the new primary key attribites
            if ~isempty(fieldDefs)
                for iField = find([fieldDefs.iskey])
                    field = fieldDefs(iField);
                    primaryKeyFields{end+1} = field.name;  %#ok<AGROW>
                    assert(~strcmpi(field.default,'NULL'), ...
                        'primary key header cannot be nullable')
                    sql = sprintf('%s%s', sql, fieldToSQL(field));
                end
            end
            
            % add secondary foreign key attributes
            for iRef = 1:length(references)
                for iField = find([references{iRef}.table.header.iskey])
                    field = references{iRef}.table.header(iField);
                    if ~ismember(field.name, primaryKeyFields)
                        nonKeyFields{end+1} = field.name; %#ok<AGROW>
                        sql = sprintf('%s%s', sql, fieldToSQL(field));
                    end
                end
            end
            
            % add dependent attributes
            if ~isempty(fieldDefs)
                for iField = find(~[fieldDefs.iskey])
                    field = fieldDefs(iField);
                    nonKeyFields{end+1} = field.name; %#ok<AGROW>
                    sql = sprintf('%s%s', sql, fieldToSQL(field));
                end
            end
            
            % add primary key declaration
            assert(~isempty(primaryKeyFields), ...
                'table must have a primary key');
            str = sprintf(',`%s`', primaryKeyFields{:});
            sql = sprintf('%sPRIMARY KEY (%s),\n',sql, str(2:end));
            
            % add foreign key declarations
            for ref = [parents references]
                fieldList = sprintf('%s,', ref{1}.primaryKey{:});
                fieldList(end)=[];
                sql = sprintf(...
                    '%sFOREIGN KEY (%s) REFERENCES %s (%s) ON UPDATE CASCADE ON DELETE RESTRICT,\n', ...
                    sql, fieldList, ref{1}.table.fullTableName, fieldList);
            end
            
            % add secondary index declarations
            for iIndex = 1:numel(indexDefs)
                assert(all(ismember(indexDefs(iIndex).attributes, ...
                    [primaryKeyFields, nonKeyFields])), ...
                    'Index definition contains invalid attribute names');
                fieldList = sprintf('`%s`,', indexDefs(iIndex).attributes{:});
                fieldList(end)=[];
                sql = sprintf(...
                    '%s%s INDEX (%s),\n', ...
                    sql, indexDefs(iIndex).unique, fieldList);
            end
            
            % close the declaration
            sql = sprintf('%s\n) ENGINE = InnoDB, COMMENT "%s$"', sql(1:end-2), tableInfo.comment);
            
            fprintf \n<SQL>\n
            disp(sql)
            fprintf </SQL>\n\n
            
            % execute declaration
            if nargout==0
                self.schema.conn.query(sql);
            end
            self.schema.reload
        end
                
        function alter(self, alter_statement)
            % dj.Table/alter
            % alter(self, alter_statement)
            % Executes an ALTER TABLE statement for this table.
            % The schema is reloaded and syncDef is called.
            sql = sprintf('ALTER TABLE  %s %s', ...
                self.fullTableName, alter_statement);
            self.schema.conn.query(sql);
            disp 'table updated'
            self.schema.reload
            self.syncDef
        end
    end
end




%          LOCAL FUNCTIONS

function str = readPercentBraceComment(filename)
% reads the initial comment block %{ ... %} in filename

f = fopen(filename, 'rt');
assert(f~=-1, 'Could not open %s', filename)
str = '';

% skip all lines that do not begin with a %{
l = fgetl(f);
while ischar(l) && ~strcmp(strtrim(l),'%{')
    l = fgetl(f);
end

if ischar(l)
    while true
        l = fgetl(f);
        assert(ischar(l), 'invalid verbatim string');
        if strcmp(strtrim(l),'%}')
            break;
        end
        str = sprintf('%s%s\n', str, l);
    end
end

fclose(f);
end



function sql = fieldToSQL(field)
% convert the structure field with header {'name' 'type' 'default' 'comment'}
% to the SQL column declaration

if strcmpi(field.default, 'NULL')
    % all nullable header default to null
    field.default = 'DEFAULT NULL';
else
    if strcmp(field.default,'<<<none>>>')
        field.default = 'NOT NULL';
    else
        % enclose value in quotes (even numeric), except special SQL values
        if ~any(strcmpi(field.default, dj.Table.mysql_constants)) && ...
                ~any(strcmp(field.default([1 end]), {'''''','""'}))
            field.default = ['"' field.default '"'];
        end
        field.default = sprintf('NOT NULL DEFAULT %s', field.default);
    end
end
sql = sprintf('`%s` %s %s COMMENT "%s",\n', ...
    field.name, field.type, field.default, field.comment);
end




function [tableInfo, parents, references, fieldDefs, indexDefs] = parseDeclaration(declaration)
parents = {};
references = {};
fieldDefs = [];
indexDefs = [];

if ischar(declaration)
    declaration = str2cell(declaration);
end
assert(iscellstr(declaration), ...
    'declaration must be a multiline string or a cellstr');

% remove empty lines and comment lines
declaration(cellfun(@(x) isempty(strtrim(x)) || strncmp('#',strtrim(x),1), declaration)) = [];

% concatenate lines that end with a backslash to the next line
i = 1;
while i<length(declaration)
    pos = regexp(declaration{i},  '\\\s*$', 'once');
    if isempty(pos)
        i = i + 1;
    else
        declaration{i} = [strtrim(declaration{i}(1:pos-1)) ' ' ...
            strtrim(declaration{i+1})];
        declaration(i+1) = [];
    end
end

% parse table schema, name, type, and comment
pat = {
    '^\s*(?<package>\w+)\.(?<className>\w+)\s*'  % package.TableName
    '\(\s*(?<tier>\w+)\s*\)\s*'                  % (tier)
    '#\s*(?<comment>\S.*\S)\s*$'                 % # comment
    };
tableInfo = regexp(declaration{1}, cat(2,pat{:}), 'names');
assert(numel(tableInfo)==1, ...
    'incorrect syntax is table declaration, line 1')
assert(ismember(tableInfo.tier, dj.Schema.allowedTiers),...
    ['Invalid tier for table ' tableInfo.className])

if nargout > 1
    % parse field declarations and references
    inKey = true;
    inIndexSection = false;
    for iLine = 2:length(declaration)
        line = strtrim(declaration{iLine});
        switch true
            case strncmp(line,'---',3)
                inKey = false;
            case strncmp(line, '+++',3)
                inIndexSection = true;
            case strncmp(line,'->',2)
                % foreign key
                p = eval(line(3:end));
                assert(isa(p, 'dj.Relvar'), ...
                    'foreign keys must be base relvars')
                if inKey
                    parents{end+1} = p;     %#ok:<AGROW>
                else
                    references{end+1} = p;   %#ok:<AGROW>
                end
            otherwise
                if ~inIndexSection
                    % parse field definition
                    fieldInfo = parseAttrDef(line, inKey);
                    fieldDefs = [fieldDefs fieldInfo];  %#ok:<AGROW>
                else
                    % parse index definition
                    indexInfo = parseIndexDef(line);
                    indexDefs = [indexDefs, indexInfo]; %#ok<AGROW>
                end
        end
    end
end
end



function fieldInfo = parseAttrDef(line, inKey)
pat = {
    '^\s*(?<name>[a-z][a-z\d_]*)\s*'  % field name
    '=\s*(?<default>\S+(\s+\S+)*)\s*' % default value
    ':\s*(?<type>\w[^#]*\S)\s*'       % datatype
    '#\s*(?<comment>\S||\S.*\S)\s*$'  % comment
    };
fieldInfo = regexp(line, cat(2,pat{:}), 'names');
if isempty(fieldInfo)
    % try no default value
    fieldInfo = regexp(line, cat(2,pat{[1 3 4]}), 'names');
    assert(~isempty(fieldInfo), ...
        'invalid field declaration line: %s', line);
    fieldInfo.default = '<<<none>>>';
end
assert(~any(fieldInfo.comment=='"'), ...
    'comments must not contain double quotes')
assert(numel(fieldInfo)==1, ...
    'Invalid field declaration "%s"', line);
fieldInfo.iskey = inKey;
end


function indexInfo = parseIndexDef(line)
pat = [
    '^\s*(?<unique>UNIQUE)?\s*' ...         % [UNIQUE]
    '(?:INDEX\s*\()' ...                    % INDEX ( 
    '(?<attributes>[^\)]+)' ...             % attr1, attr2, ...
    '\)'                                    % )
    ];
indexInfo = regexpi(line, pat, 'names');
assert(numel(indexInfo)==1 && ~isempty(indexInfo.attributes), ...
    'Invalid index declaration "%s"', line);
% Parse out and trim individual field names
attributes = textscan(indexInfo.attributes, '%s', 'delimiter',',');
attributes = cellfun(@strtrim, attributes{1}, 'UniformOutput', false);
assert(numel(unique(attributes)) == numel(attributes), ...
    'Index declaration "%s" mentions an attribute more than once', ...
    line);
indexInfo.attributes = attributes;
end


function ret = str2cell(str)
% convert a multi-line string into a cell array of one-line strings.
ret = regexp(str,'\n','split')';
ret = ret(~cellfun(@isempty, ret));  % remove empty strings
end
