/*
 | Version 10.1.1
 | Copyright 2010 Esri
 |
 | Licensed under the Apache License, Version 2.0 (the "License");
 | you may not use this file except in compliance with the License.
 | You may obtain a copy of the License at
 |
 |    http://www.apache.org/licenses/LICENSE-2.0
 |
 | Unless required by applicable law or agreed to in writing, software
 | distributed under the License is distributed on an "AS IS" BASIS,
 | WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 | See the License for the specific language governing permissions and
 | limitations under the License.
 */

// identifyLayers attribute (mkt)
package widgets.MultilayerIdentify
{
    import com.esri.ags.Graphic;
    import com.esri.ags.layers.supportClasses.Field;

	import flash.events.Event;
    import flash.utils.Dictionary;
    import flash.utils.unescapeMultiByte;

    import flashx.textLayout.conversion.TextConverter;

    import mx.collections.ArrayCollection;
	import mx.controls.Alert;
    import mx.core.UIComponent;
    import mx.formatters.CurrencyFormatter;
    import mx.formatters.DateFormatter;
    import mx.formatters.NumberFormatter;
    import mx.formatters.PhoneFormatter;
    import mx.rpc.events.FaultEvent;
    import mx.rpc.events.ResultEvent;
    import mx.rpc.http.HTTPService;

    import spark.components.RichEditableText;

    public class LayerAttributeFormatting
    {
        private const cShowAllFormat:String = "*";
        private var _format:String = cShowAllFormat;
        private const cNameFormatSplitter:String = "~";

        //---------- Save the formatting specifications ----------------------------------------------//

        public function LayerAttributeFormatting(format:String)
        {
            _format = format;
        }

        //---------- Format a feature ----------------------------------------------------------------//

        public function formatFields(feature:Graphic, fields:Array, fieldAliases:Object):UIComponent
        {
            // ActionScript does not have block-level scope
            var iField:Number;
            var name:String;
            var alias:String;

            var report:String = "";

            // Simple field name:field value pairs
            if(cShowAllFormat == _format)
            {
                var pastFirstLine:Boolean = false;
                for(name in feature.attributes)
                {
                    if("SHAPE" != name)
                    {
                        if(pastFirstLine) report += "<br />";
                        report +=
                            "<b>"
                            + formatField(name, "label", "", feature, fields, fieldAliases)
                            + ":</b>  "
                            + formatField(name, "value", "", feature, fields, fieldAliases);
                        pastFirstLine = true;
                    }
                }
            }

            // Use HTML template in format to determine selection, placement, and formatting of fields
            else
            {
                report = fillTemplate(_format, feature, fields, fieldAliases);
            }

            return htmlToRichTextBox(report);
        }

        protected function fillTemplate(template:String,
            feature:Graphic, fields:Array, fieldAliases:Object):String
        {
            var report:String = "";
            var iBegin:Number = 0;
            var iEnd:Number = 0;
            var iEnd2:Number = 0;

            while(template.length > iBegin)
            {
                iEnd = template.indexOf("{", iBegin);
                if(0 > iEnd)
                {
                    // No more embedded pieces
                    iEnd = template.length;
                    if(iBegin < iEnd) report += flash.utils.unescapeMultiByte(template.substring(iBegin, iEnd));
                    iBegin = iEnd;
                }
                else
                {
                    // Copy the part up to the embedded piece
                    if(iBegin < iEnd) report += flash.utils.unescapeMultiByte(template.substring(iBegin, iEnd));
                    iBegin = iEnd;

                    // Extract an embedded piece
                    ++iBegin;
                    if(template.length > iBegin)
                    {
                        iEnd = template.indexOf("}", iBegin);
                        if(0 > iEnd) iEnd = template.length;
                        if(iBegin < iEnd)
                        {
                            // Interpret an embedded piece containing fieldName~part[(format)], where
                            //   * "fieldName" stands for the field name
                            //   * "part" stands for "label" for reporting the field label (alias if
                            //     available; name otherwise and "value" for reporting the field value
                            //   * "(format)" stands for a format string
                            var embeddedFormat:String = template.substring(iBegin, iEnd);

                            var specParts:Array = embeddedFormat.split(cNameFormatSplitter);
                            var name:String = specParts[0];

                            var valueParts:Array = specParts[1].split("(");
                            var partRequest:String = valueParts[0];
                            var format:String = 1 < valueParts.length ?  // remove close paren
                                valueParts[1].substring(0, valueParts[1].length - 1) : "";

                            report += formatField(name, partRequest, format,
                                feature, fields, fieldAliases);
                        }
                        iBegin = iEnd + 1;
                    }
                }
            }
            return report;
        }

        protected function formatField(name:String, partRequest:Object, format:String,
            feature:Graphic, fields:Array, fieldAliases:Object):String
        {
            var alias:String = null;

            // Is there an alias?  Need to get it both for a label request and for a value request.
            if(null != fieldAliases)
            {
                alias = fieldAliases[name];
            }
            else if(null != fields)
            {
                for(var iField:int = 0; iField < fields.length; ++iField)
                {
                    if(name == fields[iField].name)
                    {
                        alias = fields[iField].alias;
                        break;
                    }
                }
            }

            // A label was requested
            if("label" == partRequest)
            {
                return ((null != alias && 0 < alias.length) ? alias : name);
            }
            // A value was requested
            else
            {
                var value:Object =
                    null != feature.attributes[name] ? feature.attributes[name] :
                    (null != feature.attributes[alias] ? feature.attributes[alias] : null);
                if(null == value) return "";

                // A date was requested
                if("date" == partRequest)
                {
                    return formatDate(new Date(value), format);
                }
                // A number was requested
                else if("number" == partRequest)
                {
                    return formatNumber(Number(value), format);
                }
                // A dollarized number was requested
                else if("currency" == partRequest)
                {
                    return formatCurrency(Number(value), format);
                }
                // A phone number was requested
                else if("phone" == partRequest)
                {
                    return formatPhone(value, format);
                }
                // A generic value was requested
                else
                {
                    return value.toString();
                }
            }
        }

        protected function formatDate(value:Date, format:String):String
        {
            var result:String = "";
            try
            {
                var formatter:DateFormatter = new DateFormatter();
                if(null != format) formatter.formatString = format;
                result = formatter.format(value);
            }
            catch(error:Error)
            {
                result = value.toString();
            }
            return result;
        }

        protected function formatNumber(value:Number, format:String):String
        {
            var result:String = "";
            try
            {
                var formatter:NumberFormatter = new NumberFormatter();

                // Format string is used to populate the properties of the NumberFormatter
                // -)+|,|.|3|nearest
                // negative sign vs. paren vs. absolute value, thousands separator, decimal separator,
                // number of decimal places
                if(null != format)
                {
                    var formatSpec:Array = format.split("|");
                    if(0 < formatSpec.length)
                    {
                        if("+" == formatSpec[0])
                        {
                            value = Math.abs(value);
                        }
                        else if(")" == formatSpec[0])
                        {
                            formatter.useNegativeSign = false;
                        }
                    }
                    if(1 < formatSpec.length)
                    {
                        formatter.useThousandsSeparator = 0 < formatSpec[1].length;
                        formatter.thousandsSeparatorTo = formatSpec[1];
                    }
                    if(2 < formatSpec.length && 0 < formatSpec[2].length
                        && formatter.useThousandsSeparator && formatSpec[1] != formatSpec[2])
                        formatter.decimalSeparatorTo = formatSpec[2];
                    if(3 < formatSpec.length)
                    {
                        try
                        {
                            formatter.precision = Number(formatSpec[3]);
                        }
                        catch(error:Error)
                        {
                            formatter.precision = -1;
                        }
                    }
                    if(4 < formatSpec.length && ("none" == formatSpec[4] || "up" == formatSpec[4]
                        || "down" == formatSpec[4] || "nearest" == formatSpec[4]))
                    {
                        formatter.rounding = formatSpec[4];
                    }
                }

                result = formatter.format(value);
            }
            catch(error:Error)
            {
                result = value.toString();
            }
            return result;
        }

        protected function formatCurrency(value:Number, format:String):String
        {
            var result:String = "";
            try
            {
                var formatter:CurrencyFormatter = new CurrencyFormatter();

                // Format string is used to populate the properties of the CurrencyFormatter
                // $|-)+|,|.|3|nearest
                // currency symbol, negative sign vs. paren vs. absolute value, thousands separator,
                // decimal separator, number of decimal places
                if(null != format)
                {
                    var formatSpec:Array = format.split("|");
                    if(0 < formatSpec.length)
                    {
                        if(0 < formatSpec[0].length)
                        {
                            formatter.currencySymbol = formatSpec[0].substr(0,1);
                            if(1 < formatSpec[0].length && "-" == formatSpec[0].substr(1,1))
                            {
                                formatter.alignSymbol = "right";
                            }
                        }
                    }
                    if(1 < formatSpec.length)
                    {
                        if("+" == formatSpec[1])
                        {
                            value = Math.abs(value);
                        }
                        else if(")" == formatSpec[1])
                        {
                            formatter.useNegativeSign = false;
                        }
                    }
                    if(2 < formatSpec.length)
                    {
                        formatter.useThousandsSeparator = 0 < formatSpec[2].length;
                        formatter.thousandsSeparatorTo = formatSpec[2];
                    }
                    if(3 < formatSpec.length && 0 < formatSpec[3].length
                        && formatter.useThousandsSeparator && formatSpec[2] != formatSpec[3])
                        formatter.decimalSeparatorTo = formatSpec[3];
                    if(4 < formatSpec.length)
                    {
                        try
                        {
                            formatter.precision = Number(formatSpec[4]);
                        }
                        catch(error:Error)
                        {
                            formatter.precision = -1;
                        }
                    }
                    if(5 < formatSpec.length && ("none" == formatSpec[5] || "up" == formatSpec[5]
                        || "down" == formatSpec[5] || "nearest" == formatSpec[5]))
                    {
                        formatter.rounding = formatSpec[5];
                    }
                }

                result = formatter.format(value);
            }
            catch(error:Error)
            {
                result = value.toString();
            }
            return result;
        }

        protected function formatPhone(value:Object, format:String):String
        {
            var result:String = "";
            try
            {
                var formatter:PhoneFormatter = new PhoneFormatter();
                result = formatter.format(value);
            }
            catch(error:Error)
            {
                result = value.toString();
            }
            return result;
        }

        protected function htmlToRichTextBox(htmlContent:String):UIComponent
        {
            // Generate a text box from the HTML
            var textBox:RichEditableText = new RichEditableText();
            textBox.textFlow = TextConverter.importToFlow(
                htmlContent, TextConverter.TEXT_FIELD_HTML_FORMAT);
            textBox.setStyle("lineHeight", "150%");  // default is 120%

			// Chris Callendar: turn off editing to make links clickable without control key
			// http://flexdevtips.blogspot.com/2010/10/displaying-html-text-in-labels.html
			textBox.editable = false;

            // Enable text wrapping: "When you specify some kind of width -- whether an explicit or
            // percent width, a maxWidth or left and right constraints -- the text wraps at the right
            // edge of the component and the text becomes vertically scrollable when there is more text
            // than fits."
            // http://help.adobe.com/en_US/FlashPlatform/reference/actionscript/3/spark/components/
            //   RichEditableText.html?filter_flex=4.1&filter_flashplayer=10.1&filter_air=2
            textBox.maxWidth = 400;

            return textBox;
        }

    }
}