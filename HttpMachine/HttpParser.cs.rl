using System;

namespace HttpMachine
{
    public class HttpParser
    {
        int cs;
        int mark;
        int qsMark;
        int fragMark;
        IHttpParserHandler parser;
        int bytesRead;

		int versionMajor = 0;
		int versionMinor = 9;

		public int MajorVersion { get { return versionMajor; } }
		public int MinorVersion { get { return versionMinor; } }

		bool gotConnectionClose;
		bool gotConnectionKeepAlive;

        // internal for testing
        internal int contentLength;
        internal bool gotContentLength;

		bool shouldKeepAlive;
		public bool ShouldKeepAlive { 
			get { 
				if (versionMajor > 0 && versionMinor > 0)
					// HTTP/1.1
					return !gotConnectionClose;
				else 
					// < HTTP/1.1
					return gotConnectionKeepAlive;
			}
		}


        %%{

        # define actions
        machine http_parser;

		action message_begin {
			parser.OnMessageBegin();
		}
        
        action matched_absolute_uri {
            Console.WriteLine("matched absolute_uri");
        }
        action matched_abs_path {
            Console.WriteLine("matched abs_path");
        }
        action matched_authority {
            Console.WriteLine("matched authority");
        }
        action matched_first_space {
            Console.WriteLine("matched first space");
        }

        action enter_method {
            mark = fpc;
        }
        
        action eof_leave_method {
            //Console.WriteLine("eof_leave_method fpc " + fpc + " mark " + mark);
            parser.OnMethod(this, new ArraySegment<byte>(data, mark, fpc - mark));
        }

        action leave_method {
            //Console.WriteLine("leave_method fpc " + fpc + " mark " + mark);
            parser.OnMethod(this, new ArraySegment<byte>(data, mark, fpc - mark));
        }
        
        action enter_request_uri {
            //Console.WriteLine("enter_request_uri fpc " + fpc);
            mark = fpc;
        }
        
        action eof_leave_request_uri {
            //Console.WriteLine("eof_leave_request_uri!! fpc " + fpc + " mark " + mark);
            parser.OnRequestUri(this, new ArraySegment<byte>(data, mark, fpc - mark));
        }

        action leave_request_uri {
            //Console.WriteLine("leave_request_uri fpc " + fpc + " mark " + mark);
            parser.OnRequestUri(this, new ArraySegment<byte>(data, mark, fpc - mark));
        }
        
        action enter_query_string {
            //Console.WriteLine("enter_query_string fpc " + fpc);
            qsMark = fpc;
        }

        action leave_query_string {
            //Console.WriteLine("leave_query_string fpc " + fpc + " qsMark " + qsMark);
            parser.OnQueryString(this, new ArraySegment<byte>(data, qsMark, fpc - qsMark));
        }
        action enter_fragment {
            //Console.WriteLine("enter_fragment fpc " + fpc);
            fragMark = fpc;
        }

        action leave_fragment {
            //Console.WriteLine("leave_fragment fpc " + fpc + " fragMark " + fragMark);
            parser.OnFragment(this, new ArraySegment<byte>(data, fragMark, fpc - fragMark));
        }

        action version_major {
			versionMajor = (char)fc - '0';
		}

		action version_minor {
			versionMinor = (char)fc - '0';
		}
        
        action enter_header_name {
            //Console.WriteLine("enter_header_name fpc " + fpc + " fc " + (char)fc);
            mark = fpc;
        }
        
        action leave_header_name {
            //Console.WriteLine("leave_header_name fpc " + fpc + " fc " + (char)fc);
            parser.OnHeaderName(this, new ArraySegment<byte>(data, mark, fpc - mark));
        }

        action leave_content_length {
            if (gotContentLength) throw new Exception("Already got Content-Length. Possible attack?");
            gotContentLength = true;
        }
        
        action enter_header_value {
            //Console.WriteLine("enter_header_value fpc " + fpc + " fc " + (char)fc);
            mark = fpc;
        }

        action header_value_char {
            //Console.WriteLine("header_value_char fpc " + fpc + " fc " + (char)fc);
            if (gotContentLength)
            {
                var cfc = (char)fc;
                if (cfc == ' ')
                {
                    fbreak;
                }

                if (cfc < '0' || cfc > '9')
                    throw new Exception("Bogus content length");

                contentLength *= 10;
                contentLength += (int)fc - (int)'0';
            }
        }
        
        action leave_header_value {
            //Console.WriteLine("leave_header_value fpc " + fpc + " fc " + (char)fc);
            parser.OnHeaderValue(this, new ArraySegment<byte>(data, mark, fpc - mark));
        }

        action leave_headers {
            parser.OnHeadersEnd();
        }

        action enter_body {
            //Console.WriteLine("enter_body fpc " + fpc);
            mark = fpc;
        }

        action body_char {
            //Console.WriteLine("body_char fpc " + fpc);
            bytesRead++;

            if (bytesRead == contentLength)
			{
				parser.OnBody(this, new ArraySegment<byte>(data, mark, fpc - mark));
				fgoto main;
			}
        }

        action leave_body {
            //Console.WriteLine("leave_body fpc " + fpc);
			var count = Math.Max(fpc - mark, contentLength - bytesRead);
            parser.OnBody(this, new ArraySegment<byte>(data, mark, count));
        }

        include http "http.rl";
        
        }%%
        
        %% write data;
        
        public HttpParser(IHttpParserHandler parser)
        {
            this.parser = parser;
            %% write init;
        }

        public int Execute(ArraySegment<byte> buf)
        {
            byte[] data = buf.Array;
            int p = buf.Offset;
            int pe = buf.Offset + buf.Count;
            //int eof = pe == 0 ? 0 : -1;
            int eof = pe;
            mark = 0;
            qsMark = 0;
            fragMark = 0;
            
            %% write exec;
            
            return p - buf.Offset;
        }
    }
}