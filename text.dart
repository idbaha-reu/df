import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:printing/printing.dart';
import 'package:universal_html/html.dart' as html;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_drawing/path_drawing.dart';
import 'dart:math' as math;

void main() {
  runApp(const QCMGeneratorApp());
}

class QCMGeneratorApp extends StatelessWidget {
  const QCMGeneratorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مولد أسئلة QCM متعدد اللغات',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2196F3),
          brightness: Brightness.light,
        ),
        textTheme: GoogleFonts.cairoTextTheme(),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2196F3),
          brightness: Brightness.dark,
        ),
        textTheme: GoogleFonts.cairoTextTheme(),
      ),
      home: const QCMGeneratorHome(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class PDFQCMGenerator {
  late GenerativeModel _model;
  String _questionType = "QCM"; // نوع الأسئلة
  String _generationMode = "أسئلة"; // وضع التوليد
  List<String> _processedTexts = []; // قائمة النصوص المعالجة

  void initialize(String apiKey) {
    _model = GenerativeModel(
      model: 'gemini-2.0-flash',
      apiKey: apiKey,
    );
  }

  void setQuestionType(String type) {
    _questionType = type;
  }

  void setGenerationMode(String mode) {
    _generationMode = mode;
  }

  void clearProcessedTexts() {
    _processedTexts.clear();
  }

  List<String> getProcessedTexts() {
    return _processedTexts;
  }

  String detectLanguage(String text) {
    if (text.isEmpty) return 'غير محدد';

    String sampleText = text.length > 1000 ? text.substring(0, 1000) : text;

    final langPatterns = {
      'العربية': RegExp(
          r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]'),
      'English': RegExp(r'[a-zA-Z]'),
      'Français': RegExp(r'[àâäéèêëïîôöùûüÿçÀÂÄÉÈÊËÏÎÔÖÙÛÜŸÇ]'),
      'Español': RegExp(r'[áéíóúüñÁÉÍÓÚÜÑ¿¡]'),
      'Deutsch': RegExp(r'[äöüßÄÖÜ]'),
      'Italiano': RegExp(r'[àèéìíîòóùúÀÈÉÌÍÎÒÓÙÚ]'),
    };

    Map<String, int> matches = {};
    for (var entry in langPatterns.entries) {
      matches[entry.key] = entry.value.allMatches(sampleText).length;
    }

    if (matches['العربية']! > sampleText.length * 0.1) {
      return 'العربية';
    }

    var maxEntry = matches.entries.reduce((a, b) => a.value > b.value ? a : b);
    return maxEntry.value > 0 ? maxEntry.key : 'English';
  }

  // استخراج النص من PDF باستخدام Gemini AI مباشرة
  Future<String> extractTextFromPDFWithAI(Uint8List pdfBytes) async {
    try {
      String base64Pdf = base64Encode(pdfBytes);

      final prompt = """
أنت خبير في استخراج النص من ملفات PDF. 
استخرج جميع النصوص الموجودة في هذا الملف واكتبها بوضوح.
تجاهل أي بيانات تقنية أو metadata.
ركز فقط على النص المقروء والمفهوم.
إذا كان النص بالعربية، احتفظ بالتشكيل.
إذا كان باللغة الإنجليزية أو أي لغة أخرى، احتفظ بالتنسيق الأصلي.
""";

      final content = [
        Content.multi([
          TextPart(prompt),
          DataPart('application/pdf', pdfBytes),
        ])
      ];

      final response = await _model.generateContent(content);
      String extractedText = response.text ?? '';

      if (extractedText.trim().isEmpty) {
        throw Exception('لم يتم العثور على نص قابل للقراءة في PDF');
      }

      _processedTexts.add(extractedText.trim());
      return extractedText.trim();
    } catch (e) {
      throw Exception('خطأ في استخراج النص من PDF: ${e.toString()}');
    }
  }

  // دمج النصوص المعالجة
  String getCombinedText() {
    return _processedTexts.join('\n\n---\n\n');
  }

  Future<List<Map<String, dynamic>>> generateQCMQuestions(
    String text,
    int numQuestions,
    String language,
    String difficulty,
  ) async {
    String instructions;
    String questionType = _questionType == "QCM" ? "اختيار من متعدد" : "مفتوحة";

    if (language == "العربية" || language == "ar") {
      instructions = """
أنت خبير في إنشاء أسئلة $questionType باللغة العربية.

تعليمات مهمة:
1. اكتب الأسئلة باللغة العربية
${_questionType == "QCM" ? """2. كل سؤال يجب أن يحتوي على 4 خيارات (أ، ب، ج، د)
3. حدد الإجابة الصحيحة
4. اجعل الخيارات منطقية ومعقولة""" : """2. اكتب أسئلة مفتوحة تتطلب إجابات تفصيلية
3. تأكد من أن الأسئلة واضحة ومباشرة
4. أضف تلميحات أو نقاط يجب تغطيتها في الإجابة"""}
5. اجعل الأسئلة متنوعة ومناسبة لمستوى $difficulty

اكتب الإجابة في شكل JSON بالتنسيق التالي:
{
  "questions": [
    {
      "question": "نص السؤال هنا؟",
      ${_questionType == "QCM" ? """
      "options": {
        "أ": "الخيار الأول",
        "ب": "الخيار الثاني", 
        "ج": "الخيار الثالث",
        "د": "الخيار الرابع"
      },
      "correct_answer": "أ",""" : ""}
      "explanation": "شرح الإجابة الصحيحة"
    }
  ]
}
""";
    } else {
      instructions = """
You are an expert in creating ${_questionType == "QCM" ? "Multiple Choice Questions (MCQ)" : "Open-Ended Questions"}.

Important instructions:
1. Write questions in the same language as the text ($language)
${_questionType == "QCM" ? """2. Each question should have 4 options (A, B, C, D)
3. Identify the correct answer
4. Make options logical and reasonable""" : """2. Write open-ended questions that require detailed answers
3. Ensure questions are clear and direct
4. Add hints or points that should be covered in the answer"""}
5. Make questions varied and appropriate for $difficulty level

Write the answer in JSON format as follows:
{
  "questions": [
    {
      "question": "Question text here?",
      ${_questionType == "QCM" ? """
      "options": {
        "A": "First option",
        "B": "Second option", 
        "C": "Third option",
        "D": "Fourth option"
      },
      "correct_answer": "A",""" : ""}
      "explanation": "Explanation of the correct answer"
    }
  ]
}
""";
    }

    String prompt = """
$instructions

Create $numQuestions multiple choice questions based on the following text:

Text:
${text.length > 8000 ? text.substring(0, 8000) : text}
""";

    try {
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);

      String responseText = response.text ?? '';

      final jsonMatch =
          RegExp(r'\{.*\}', dotAll: true).firstMatch(responseText);
      if (jsonMatch != null) {
        String jsonText = jsonMatch.group(0)!;
        Map<String, dynamic> questionsData = json.decode(jsonText);
        return List<Map<String, dynamic>>.from(
            questionsData['questions'] ?? []);
      } else {
        throw Exception("لم يتم العثور على تنسيق JSON صحيح في الاستجابة");
      }
    } catch (e) {
      throw Exception("خطأ في توليد الأسئلة: ${e.toString()}");
    }
  }

  Future<String> generateSummary(String text, String language) async {
    String instructions;
    if (language == "العربية" || language == "ar") {
      instructions = """
أنت خبير في تلخيص النصوص التعليمية باللغة العربية.

تعليمات مهمة:
1. قم بتلخيص النص بشكل واضح ومختصر
2. حدد النقاط الرئيسية والأفكار المهمة
3. نظم المعلومات بشكل منطقي
4. استخدم عناوين فرعية لتنظيم المحتوى
5. أضف نقاط مهمة في نهاية الملخص

اكتب الملخص باللغة العربية وبشكل منظم.
""";
    } else {
      instructions = """
You are an expert in summarizing educational texts.

Important instructions:
1. Summarize the text clearly and concisely
2. Identify main points and key ideas
3. Organize information logically
4. Use subheadings to structure the content
5. Add important points at the end of the summary

Write the summary in $language in a well-organized format.
""";
    }

    String prompt = """
$instructions

Summarize the following text:

Text:
${text.length > 8000 ? text.substring(0, 8000) : text}
""";

    try {
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      return response.text ?? '';
    } catch (e) {
      throw Exception("خطأ في توليد الملخص: ${e.toString()}");
    }
  }

  Future<String> generateMindMap(String text, String language) async {
    String instructions;
    if (language == "العربية" || language == "ar") {
      instructions = """
أنت خبير في إنشاء خطاطات ذهنية باللغة العربية.

تعليمات مهمة:
1. قم بتحليل النص واستخراج الأفكار الرئيسية
2. نظم الأفكار في شكل هرمي
3. استخدم عناوين قصيرة وواضحة
4. أضف روابط منطقية بين الأفكار
5. استخدم رموز وألوان مناسبة

اكتب الهيكل في شكل JSON بالتنسيق التالي:
{
  "title": "العنوان الرئيسي",
  "nodes": [
    {
      "id": "1",
      "text": "الفكرة الرئيسية الأولى",
      "color": "#FF5733",
      "children": [
        {
          "id": "1.1",
          "text": "فكرة فرعية 1",
          "color": "#33FF57"
        },
        {
          "id": "1.2",
          "text": "فكرة فرعية 2",
          "color": "#3357FF"
        }
      ]
    }
  ]
}
""";
    } else {
      instructions = """
You are an expert in creating mind maps.

Important instructions:
1. Analyze the text and extract main ideas
2. Organize ideas in a hierarchical structure
3. Use short and clear titles
4. Add logical connections between ideas
5. Use appropriate symbols and colors

Write the structure in JSON format as follows:
{
  "title": "Main Title",
  "nodes": [
    {
      "id": "1",
      "text": "Main Idea 1",
      "color": "#FF5733",
      "children": [
        {
          "id": "1.1",
          "text": "Sub-idea 1",
          "color": "#33FF57"
        },
        {
          "id": "1.2",
          "text": "Sub-idea 2",
          "color": "#3357FF"
        }
      ]
    }
  ]
}
""";
    }

    String prompt = """
$instructions

Create a mind map structure based on the following text:

Text:
${text.length > 8000 ? text.substring(0, 8000) : text}
""";

    try {
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      return response.text ?? '';
    } catch (e) {
      throw Exception("خطأ في توليد الخطاطة الذهنية: ${e.toString()}");
    }
  }

  Future<Uint8List> convertMindMapToImage(String mindMapStructure) async {
    try {
      // Ici, vous devrez implémenter la logique de conversion de la structure JSON en image
      // Vous pouvez utiliser des packages comme flutter_svg ou custom_paint pour dessiner la carte mentale
      // Pour l'instant, nous retournons une image de test
      return Uint8List.fromList([]); // À implémenter
    } catch (e) {
      throw Exception("خطأ في تحويل الخطاطة الذهنية إلى صورة: ${e.toString()}");
    }
  }
}

class QCMGeneratorHome extends StatefulWidget {
  const QCMGeneratorHome({super.key});

  @override
  State<QCMGeneratorHome> createState() => _QCMGeneratorHomeState();
}

class _QCMGeneratorHomeState extends State<QCMGeneratorHome>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  Map<String, dynamic>? _mindMapData;
  String _mindMapImagePath = '';

  final TextEditingController _textController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();

  final PDFQCMGenerator _generator = PDFQCMGenerator();

  String _inputMethod = "✏️ لصق نص مباشرة";
  String _detectedLanguage = "";
  int _numQuestions = 5;
  String _difficulty = "متوسط";
  String _forceLanguage = "تلقائي (حسب النص)";
  String _questionType = "QCM";
  String _generationMode = "أسئلة";
  List<Map<String, dynamic>> _questions = [];
  bool _isLoading = false;
  String _summary = "";
  List<String> _uploadedFiles = []; // قائمة الملفات المرفوعة

  final List<String> _inputMethods = ["✏️ لصق نص مباشرة", "📄 رفع ملف PDF"];
  final List<String> _difficulties = ["سهل", "متوسط", "صعب", "مختلط"];
  final List<String> _languages = [
    "تلقائي (حسب النص)",
    "العربية",
    "English",
    "Français"
  ];
  final List<String> _questionTypes = ["QCM", "أسئلة مفتوحة"];
  final List<String> _generationModes = [
    "أسئلة",
    "تلخيص",
    "امتحان تجريبي",
    "خطاطة ذهنية"
  ];
  final List<String> _examTypes = ["QCM فقط", "مفتوحة فقط", "كلاهما"];
  String _examType = "QCM فقط";

  int _selectedNavIndex = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    _animationController.forward();
    _loadApiKey();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _textController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _generateMindMap() async {
    try {
      String contentLanguage = _forceLanguage == "تلقائي (حسب النص)"
          ? _detectedLanguage
          : _forceLanguage;

      String mindMapStructure = await _generator.generateMindMap(
        _textController.text,
        contentLanguage,
      );

      // استخراج JSON من النص المُولد
      final jsonMatch =
          RegExp(r'\{.*\}', dotAll: true).firstMatch(mindMapStructure);
      if (jsonMatch != null) {
        String jsonText = jsonMatch.group(0)!;
        Map<String, dynamic> mindMapData = json.decode(jsonText);

        setState(() {
          _mindMapData = mindMapData;
          _isLoading = false;
        });

        _showSnackBar('✅ تم توليد الخطاطة الذهنية بنجاح!', Colors.green);
      } else {
        throw Exception("فشل في تحليل بيانات الخطاطة الذهنية");
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showSnackBar(
          'خطأ في توليد الخطاطة الذهنية: ${e.toString()}', Colors.red);
    }
  }

  Future<void> _generatePDF() async {
    if (_questions.isEmpty && _summary.isEmpty && _mindMapData == null) {
      _showSnackBar('لا توجد بيانات للتصدير', Colors.orange);
      return;
    }

    try {
      final pdf = pw.Document();

      if (_generationMode == "خطاطة ذهنية" && _mindMapData != null) {
        await _generateMindMapPDF(pdf);
      } else if (_generationMode == "امتحان تجريبي" && _questions.isNotEmpty) {
        await _generateExamPDF(pdf);
      } else if (_generationMode == "تلخيص" && _summary.isNotEmpty) {
        await _generateSummaryPDF(pdf);
      } else {
        await _generateQuestionsPDF(pdf);
      }

      final bytes = await pdf.save();

      if (kIsWeb) {
        final blob = html.Blob([bytes], 'application/pdf');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.document.createElement('a') as html.AnchorElement
          ..href = url
          ..style.display = 'none'
          ..download =
              '${_generationMode}_${DateTime.now().millisecondsSinceEpoch}.pdf';
        html.document.body!.children.add(anchor);
        anchor.click();
        html.document.body!.children.remove(anchor);
        html.Url.revokeObjectUrl(url);
      } else {
        await Printing.layoutPdf(onLayout: (format) async => bytes);
      }

      _showSnackBar('✅ تم إنشاء PDF بنجاح!', Colors.green);
    } catch (e) {
      _showSnackBar('خطأ في إنشاء PDF: ${e.toString()}', Colors.red);
    }
  }

  // إنشاء PDF للخطاطة الذهنية
  Future<void> _generateMindMapPDF(pw.Document pdf) async {
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(
                level: 0,
                child: pw.Text(
                  _mindMapData!['title'] ?? 'الخطاطة الذهنية',
                  style: pw.TextStyle(
                      fontSize: 24, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 20),
              ..._buildMindMapPDFNodes(_mindMapData!['nodes'] ?? []),
            ],
          );
        },
      ),
    );
  }

  // بناء عقد الخطاطة الذهنية في PDF
  List<pw.Widget> _buildMindMapPDFNodes(List<dynamic> nodes) {
    List<pw.Widget> widgets = [];

    for (int i = 0; i < nodes.length; i++) {
      var node = nodes[i];

      // العقدة الرئيسية
      widgets.add(
        pw.Container(
          margin: const pw.EdgeInsets.symmetric(vertical: 10),
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.blue, width: 2),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Text(
            node['text'] ?? '',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
        ),
      );

      // العقد الفرعية
      if (node['children'] != null) {
        for (var child in node['children']) {
          widgets.add(
            pw.Container(
              margin: const pw.EdgeInsets.only(left: 30, top: 5, bottom: 5),
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey, width: 1),
                borderRadius: pw.BorderRadius.circular(5),
              ),
              child: pw.Text(
                '• ${child['text'] ?? ''}',
                style: const pw.TextStyle(fontSize: 14),
              ),
            ),
          );
        }
      }

      widgets.add(pw.SizedBox(height: 10));
    }

    return widgets;
  }

  // إنشاء PDF للامتحان التجريبي
  Future<void> _generateExamPDF(pw.Document pdf) async {
    pdf.addPage(
      pw.MultiPage(
        build: (pw.Context context) => [
          pw.Header(
            level: 0,
            child: pw.Text(
              'امتحان تجريبي - ${_questions.length} سؤال',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 20),
          ...List.generate(_questions.length, (index) {
            final q = _questions[index];
            return pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 20),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'سؤال ${index + 1}: ${q['question']}',
                    style: pw.TextStyle(
                        fontSize: 14, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 8),
                  if (q['options'] != null) ...[
                    ...((q['options'] as Map<String, dynamic>)
                        .entries
                        .map((entry) {
                      return pw.Padding(
                        padding: const pw.EdgeInsets.only(left: 20, bottom: 4),
                        child: pw.Text('${entry.key}. ${entry.value}'),
                      );
                    }).toList()),
                  ],
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'الإجابة: ${q['correct_answer'] ?? 'مفتوحة'}',
                    style: pw.TextStyle(fontSize: 12, color: PdfColors.green),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // إنشاء PDF للملخص
  Future<void> _generateSummaryPDF(pw.Document pdf) async {
    pdf.addPage(
      pw.MultiPage(
        build: (pw.Context context) => [
          pw.Header(
            level: 0,
            child: pw.Text(
              'ملخص الدرس',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            _summary,
            style: const pw.TextStyle(fontSize: 12, lineSpacing: 1.5),
          ),
        ],
      ),
    );
  }

  // إنشاء PDF للأسئلة العادية
  Future<void> _generateQuestionsPDF(pw.Document pdf) async {
    pdf.addPage(
      pw.MultiPage(
        build: (pw.Context context) => [
          pw.Header(
            level: 0,
            child: pw.Text(
              'أسئلة ${_questionType} - ${_questions.length} سؤال',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 20),
          ...List.generate(_questions.length, (index) {
            final q = _questions[index];
            return pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 15),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'سؤال ${index + 1}: ${q['question']}',
                    style: pw.TextStyle(
                        fontSize: 14, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 8),
                  if (q['options'] != null) ...[
                    ...((q['options'] as Map<String, dynamic>)
                        .entries
                        .map((entry) {
                      bool isCorrect = entry.key == q['correct_answer'];
                      return pw.Padding(
                        padding: const pw.EdgeInsets.only(left: 20, bottom: 4),
                        child: pw.Text(
                          '${entry.key}. ${entry.value}${isCorrect ? ' ✓' : ''}',
                          style: pw.TextStyle(
                            color:
                                isCorrect ? PdfColors.green : PdfColors.black,
                            fontWeight: isCorrect
                                ? pw.FontWeight.bold
                                : pw.FontWeight.normal,
                          ),
                        ),
                      );
                    }).toList()),
                  ],
                  if (q['explanation'] != null) ...[
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'الشرح: ${q['explanation']}',
                      style:
                          pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // تحديث دالة _buildMainContent لعرض الخطاطة الذهنية
  Widget _buildMainContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 60),

          // بطاقة الإعدادات
          _buildSettingsCard(),

          const SizedBox(height: 16),

          // بطاقة النص المدخل
          _buildInputCard(),

          const SizedBox(height: 16),

          // زر التوليد
          _buildGenerateButton(),

          const SizedBox(height: 20),

          // عرض النتائج
          if (_isLoading) _buildLoadingWidget(),
          if (!_isLoading && _questions.isNotEmpty) _buildQuestionsDisplay(),
          if (!_isLoading && _summary.isNotEmpty) _buildSummaryDisplay(),
          if (!_isLoading && _mindMapData != null) _buildMindMapDisplay(),

          const SizedBox(height: 100),
        ],
      ),
    );
  }

  // عرض الخطاطة الذهنية
  Widget _buildMindMapDisplay() {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_tree, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                Text(
                  _mindMapData!['title'] ?? 'الخطاطة الذهنية',
                  style: GoogleFonts.cairo(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // عرض العقد
            ...(_mindMapData!['nodes'] as List<dynamic>).map((node) {
              return _buildMindMapNode(node);
            }).toList(),

            const SizedBox(height: 20),

            // رسم تفاعلي للخطاطة الذهنية
            Container(
              height: 400,
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: CustomPaint(
                painter: MindMapPainter(_mindMapData!),
                size: Size.infinite,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // بطاقة الإعدادات
  Widget _buildSettingsCard() {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                Text(
                  '⚙️ إعدادات التوليد',
                  style: GoogleFonts.cairo(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // مفتاح API
            Text(
              '🔑 مفتاح Gemini API',
              style: GoogleFonts.cairo(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _apiKeyController,
              decoration: InputDecoration(
                hintText: 'أدخل مفتاح API من Google AI Studio',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
                prefixIcon: const Icon(Icons.key),
                suffixIcon: IconButton(
                  icon: Icon(_apiKeyController.text.isNotEmpty
                      ? Icons.visibility_off
                      : Icons.visibility),
                  onPressed: () {
                    // تبديل إظهار/إخفاء المفتاح
                  },
                ),
              ),
              obscureText: true,
              onChanged: (value) {
                setState(() {});
              },
            ),
            const SizedBox(height: 4),
            Text(
              'احصل على مفتاح مجاني من: aistudio.google.com',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),

            const SizedBox(height: 16),

            // وضع التوليد
            Text(
              '🎯 وضع التوليد',
              style: GoogleFonts.cairo(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _generationMode,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              items: _generationModes.map((mode) {
                return DropdownMenuItem(
                  value: mode,
                  child: Text(mode, style: GoogleFonts.cairo()),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _generationMode = value!;
                });
              },
            ),

            // إعدادات إضافية حسب الوضع
            if (_generationMode == "أسئلة" ||
                _generationMode == "امتحان تجريبي") ...[
              const SizedBox(height: 16),

              // نوع الأسئلة
              if (_generationMode == "أسئلة") ...[
                Text(
                  '📝 نوع الأسئلة',
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _questionType,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  items: _questionTypes.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(type, style: GoogleFonts.cairo()),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _questionType = value!;
                    });
                  },
                ),
              ],

              // نوع الامتحان التجريبي
              if (_generationMode == "امتحان تجريبي") ...[
                Text(
                  '📋 نوع الامتحان',
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _examType,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  items: _examTypes.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(type, style: GoogleFonts.cairo()),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _examType = value!;
                    });
                  },
                ),
              ],

              const SizedBox(height: 16),

              // عدد الأسئلة
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '🔢 عدد الأسئلة: $_numQuestions',
                          style: GoogleFonts.cairo(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Slider(
                          value: _numQuestions.toDouble(),
                          min: 1,
                          max: 20,
                          divisions: 19,
                          onChanged: (value) {
                            setState(() {
                              _numQuestions = value.round();
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),

                  // مستوى الصعوبة
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '⚡ مستوى الصعوبة',
                          style: GoogleFonts.cairo(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _difficulty,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            isDense: true,
                          ),
                          items: _difficulties.map((difficulty) {
                            return DropdownMenuItem(
                              value: difficulty,
                              child:
                                  Text(difficulty, style: GoogleFonts.cairo()),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _difficulty = value!;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 16),

            // اللغة
            Text(
              '🌐 اللغة المطلوبة',
              style: GoogleFonts.cairo(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _forceLanguage,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              items: _languages.map((language) {
                return DropdownMenuItem(
                  value: language,
                  child: Text(language, style: GoogleFonts.cairo()),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _forceLanguage = value!;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  // بطاقة إدخال النص
  Widget _buildInputCard() {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.text_fields, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                Text(
                  '📝 مصدر النص',
                  style: GoogleFonts.cairo(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // طريقة الإدخال
            DropdownButtonFormField<String>(
              value: _inputMethod,
              decoration: InputDecoration(
                labelText: 'طريقة الإدخال',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              items: _inputMethods.map((method) {
                return DropdownMenuItem(
                  value: method,
                  child: Text(method, style: GoogleFonts.cairo()),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _inputMethod = value!;
                });
              },
            ),

            const SizedBox(height: 16),

            // النص أو رفع الملف
            if (_inputMethod == "✏️ لصق نص مباشرة") ...[
              TextField(
                controller: _textController,
                maxLines: 8,
                decoration: InputDecoration(
                  hintText: 'الصق النص التعليمي هنا...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                onChanged: (value) {
                  setState(() {
                    _detectedLanguage = _generator.detectLanguage(value);
                  });
                },
              ),
            ] else ...[
              // رفع ملف PDF
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.grey.shade300,
                    style: BorderStyle.solid,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey.shade50,
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.cloud_upload,
                      size: 48,
                      color: Theme.of(context).primaryColor,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'اختر ملفات PDF',
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'يمكنك رفع ملف أو أكثر (PDF فقط)',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _pickPDFFiles,
                      icon: const Icon(Icons.file_upload),
                      label: Text(
                        'رفع ملفات PDF',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // عرض الملفات المرفوعة
              if (_uploadedFiles.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '✅ الملفات المرفوعة (${_uploadedFiles.length}):',
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w600,
                          color: Colors.green.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...(_uploadedFiles
                          .map((file) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  children: [
                                    Icon(Icons.picture_as_pdf,
                                        size: 16, color: Colors.red.shade600),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        file,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.green.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ))
                          .toList()),
                    ],
                  ),
                ),
              ],
            ],

            const SizedBox(height: 12),

            // معلومات النص
            if (_textController.text.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).primaryColor.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Theme.of(context).primaryColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'الطول: ${_textController.text.length} حرف' +
                            (_detectedLanguage.isNotEmpty
                                ? ' • اللغة المكتشفة: $_detectedLanguage'
                                : ''),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // زر التوليد
  Widget _buildGenerateButton() {
    bool canGenerate = _textController.text.trim().isNotEmpty &&
        _apiKeyController.text.trim().isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: canGenerate && !_isLoading ? _generateContent : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: canGenerate
              ? Theme.of(context).primaryColor
              : Colors.grey.shade400,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: canGenerate ? 8 : 2,
        ),
        child: _isLoading
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _generationMode == "أسئلة"
                        ? Icons.quiz
                        : _generationMode == "تلخيص"
                            ? Icons.summarize
                            : _generationMode == "امتحان تجريبي"
                                ? Icons.assignment
                                : Icons.account_tree,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _isLoading ? 'جاري التوليد...' : 'توليد $_generationMode',
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // عنصر التحميل
  Widget _buildLoadingWidget() {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              'جاري توليد $_generationMode...',
              style: GoogleFonts.cairo(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'قد يستغرق هذا بضع ثوانٍ',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // عرض الأسئلة
  Widget _buildQuestionsDisplay() {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.quiz, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                Text(
                  '$_questionType - ${_questions.length} سؤال',
                  style: GoogleFonts.cairo(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // الأسئلة
            ...List.generate(_questions.length, (index) {
              final question = _questions[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'سؤال ${index + 1}',
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      question['question'] ?? '',
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (question['options'] != null) ...[
                      const SizedBox(height: 12),
                      ...((question['options'] as Map<String, dynamic>)
                          .entries
                          .map((entry) {
                        bool isCorrect =
                            entry.key == question['correct_answer'];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color:
                                isCorrect ? Colors.green.shade50 : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isCorrect
                                  ? Colors.green.shade300
                                  : Colors.grey.shade300,
                              width: isCorrect ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: isCorrect
                                      ? Colors.green
                                      : Colors.grey.shade300,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    entry.key,
                                    style: TextStyle(
                                      color: isCorrect
                                          ? Colors.white
                                          : Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  entry.value,
                                  style: GoogleFonts.cairo(
                                    fontSize: 14,
                                    color: isCorrect
                                        ? Colors.green.shade700
                                        : Colors.black,
                                    fontWeight: isCorrect
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (isCorrect)
                                Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                  size: 20,
                                ),
                            ],
                          ),
                        );
                      }).toList()),
                    ],
                    if (question['explanation'] != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.lightbulb_outline,
                              color: Colors.blue.shade600,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                question['explanation'],
                                style: GoogleFonts.cairo(
                                  fontSize: 12,
                                  color: Colors.blue.shade700,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // عرض الملخص
  Widget _buildSummaryDisplay() {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.summarize, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                Text(
                  '📄 ملخص النص',
                  style: GoogleFonts.cairo(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                _summary,
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  height: 1.6,
                  color: Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // إضافة دالة _showSettings المفقودة
  void _showSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'إعدادات التطبيق',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.info),
              title: Text('حول التطبيق', style: GoogleFonts.cairo()),
              subtitle: Text('مولد أسئلة QCM متعدد اللغات',
                  style: GoogleFonts.cairo()),
            ),
            ListTile(
              leading: Icon(Icons.help),
              title: Text('المساعدة', style: GoogleFonts.cairo()),
              subtitle:
                  Text('كيفية استخدام التطبيق', style: GoogleFonts.cairo()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('إغلاق', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }

  // بناء عقدة واحدة من الخطاطة الذهنية
  Widget _buildMindMapNode(Map<String, dynamic> node) {
    Color nodeColor = _parseColor(node['color'] ?? '#2196F3');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // العقدة الرئيسية
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: nodeColor.withOpacity(0.1),
              border: Border.all(color: nodeColor, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              node['text'] ?? '',
              style: GoogleFonts.cairo(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: nodeColor,
              ),
            ),
          ),

          // العقد الفرعية
          if (node['children'] != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Column(
                children: (node['children'] as List<dynamic>).map((child) {
                  Color childColor = _parseColor(child['color'] ?? '#9E9E9E');
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: childColor.withOpacity(0.1),
                      border: Border.all(color: childColor, width: 1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.circle, size: 8, color: childColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            child['text'] ?? '',
                            style: GoogleFonts.cairo(
                              fontSize: 14,
                              color: childColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // تحويل النص اللوني إلى Color
  Color _parseColor(String colorString) {
    try {
      colorString = colorString.replaceAll('#', '');
      if (colorString.length == 6) {
        colorString = 'FF$colorString';
      }
      return Color(int.parse(colorString, radix: 16));
    } catch (e) {
      return Colors.blue; // لون افتراضي
    }
  }

  Future<void> _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('gemini_api_key') ?? '';
    setState(() {
      _apiKeyController.text = apiKey;
    });
  }

  Future<void> _saveApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', _apiKeyController.text);
  }

  Future<void> _pickPDFFiles() async {
    if (_apiKeyController.text.trim().isEmpty) {
      _showSnackBar('يرجى إدخال مفتاح Gemini API أولاً لاستخراج النص من PDF',
          Colors.orange);
      return;
    }

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _isLoading = true;
        });

        _generator.clearProcessedTexts();
        _uploadedFiles.clear();

        _generator.initialize(_apiKeyController.text.trim());

        for (var file in result.files) {
          if (file.bytes == null) continue;
          try {
            String text =
                await _generator.extractTextFromPDFWithAI(file.bytes!);
            _uploadedFiles.add(file.name);
          } catch (e) {
            _showSnackBar('خطأ في معالجة الملف ${file.name}: ${e.toString()}',
                Colors.red);
          }
        }

        setState(() {
          _textController.text = _generator.getCombinedText();
          _detectedLanguage = _generator.detectLanguage(_textController.text);
          _isLoading = false;
        });

        _showSnackBar('✅ تم استخراج النص من ${_uploadedFiles.length} ملف بنجاح',
            Colors.green);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showSnackBar('خطأ في قراءة الملفات: ${e.toString()}', Colors.red);
    }
  }

  Future<void> _generateContent() async {
    if (_textController.text.trim().isEmpty) {
      _showSnackBar('يرجى إدخال النص أو رفع ملف PDF', Colors.orange);
      return;
    }

    if (_apiKeyController.text.trim().isEmpty) {
      _showSnackBar('يرجى إدخال مفتاح Gemini API', Colors.orange);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _saveApiKey();
      _generator.initialize(_apiKeyController.text.trim());
      _generator.setGenerationMode(_generationMode);
      String contentLanguage = _forceLanguage == "تلقائي (حسب النص)"
          ? _detectedLanguage
          : _forceLanguage;
      if (_generationMode == "أسئلة") {
        _generator.setQuestionType(_questionType);
        List<Map<String, dynamic>> questions =
            await _generator.generateQCMQuestions(
          _textController.text,
          _numQuestions,
          contentLanguage,
          _difficulty,
        );
        setState(() {
          _questions = questions;
          _isLoading = false;
        });
        if (questions.isNotEmpty) {
          _showSnackBar(
              '🎉 تم توليد ${questions.length} سؤال بنجاح!', Colors.green);
        } else {
          _showSnackBar('فشل في توليد الأسئلة', Colors.red);
        }
      } else if (_generationMode == "تلخيص") {
        String summary = await _generator.generateSummary(
          _textController.text,
          contentLanguage,
        );
        setState(() {
          _summary = summary;
          _isLoading = false;
        });
        _showSnackBar('✅ تم توليد الملخص بنجاح!', Colors.green);
      } else if (_generationMode == "امتحان تجريبي") {
        List<Map<String, dynamic>> examQuestions = [];
        int qcmCount = _numQuestions;
        int openCount = 0;
        if (_examType == "كلاهما") {
          qcmCount = (_numQuestions / 2).ceil();
          openCount = _numQuestions - qcmCount;
        } else if (_examType == "مفتوحة فقط") {
          qcmCount = 0;
          openCount = _numQuestions;
        } else {
          openCount = 0;
        }
        // توليد QCM
        if (qcmCount > 0) {
          _generator.setQuestionType("QCM");
          List<Map<String, dynamic>> qcm =
              await _generator.generateQCMQuestions(
            _textController.text,
            qcmCount,
            contentLanguage,
            _difficulty,
          );
          examQuestions.addAll(qcm);
        }
        // توليد أسئلة مفتوحة
        if (openCount > 0) {
          _generator.setQuestionType("أسئلة مفتوحة");
          List<Map<String, dynamic>> open =
              await _generator.generateQCMQuestions(
            _textController.text,
            openCount,
            contentLanguage,
            _difficulty,
          );
          examQuestions.addAll(open);
        }
        setState(() {
          _questions = examQuestions;
          _isLoading = false;
        });
        if (examQuestions.isNotEmpty) {
          _showSnackBar(
              '🎉 تم توليد امتحان تجريبي بـ ${examQuestions.length} سؤال!',
              Colors.green);
        } else {
          _showSnackBar('فشل في توليد الامتحان التجريبي', Colors.red);
        }
      } else if (_generationMode == "خطاطة ذهنية") {
        await _generateMindMap();
        return;
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showSnackBar('خطأ: ${e.toString()}', Colors.red);
    }
  }

  void _exportQuestions(String format) {
    if (_questions.isEmpty && _summary.isEmpty) return;

    String content = '';
    String fileName = _generationMode == "أسئلة"
        ? 'qcm_questions_${_numQuestions}_${_detectedLanguage}'
        : 'summary_${_detectedLanguage}';

    switch (format) {
      case 'json':
        if (_generationMode == "أسئلة") {
          content = const JsonEncoder.withIndent('  ').convert(_questions);
        } else {
          content = const JsonEncoder.withIndent('  ')
              .convert({"summary": _summary, "language": _detectedLanguage});
        }
        fileName += '.json';
        break;
      case 'txt':
        if (_generationMode == "أسئلة") {
          for (int i = 0; i < _questions.length; i++) {
            final q = _questions[i];
            content += 'Question  ${i + 1}: ${q['question']}\n';
            final options = q['options'] as Map<String, dynamic>;
            options.forEach((key, value) {
              content += '$key. $value\n';
            });
            content += 'الإجابة الصحيحة: ${q['correct_answer']}\n\n';
          }
        } else {
          content = _summary;
        }
        fileName += '.txt';
        break;
      case 'html':
        content = _generateHTMLContent();
        fileName += '.html';
        break;
    }

    if (kIsWeb) {
      Clipboard.setData(ClipboardData(text: content));
      _showSnackBar('تم نسخ المحتوى للحافظة', Colors.green);
    } else {
      Share.share(content, subject: fileName);
    }
  }

  String _generateHTMLContent() {
    String html = '''
<!DOCTYPE html>
<html dir="${_detectedLanguage == 'العربية' ? 'rtl' : 'ltr'}">
<head>
    <meta charset="UTF-8">
    <title>${_generationMode == "أسئلة" ? "أسئلة QCM" : "ملخص الدرس"}</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .question { margin: 20px 0; page-break-inside: avoid; }
        .options { margin: 10px 0; }
        .correct { color: green; font-weight: bold; }
        .summary { line-height: 1.6; }
    </style>
</head>
<body>
    <h1>${_generationMode == "أسئلة" ? "أسئلة الاختيار من متعدد" : "ملخص الدرس"}</h1>
''';

    if (_generationMode == "أسئلة") {
      for (int i = 0; i < _questions.length; i++) {
        final q = _questions[i];
        html += '''
    <div class="question">
        <h3>Question  ${i + 1}: ${q['question']}</h3>
        <div class="options">
''';
        final options = q['options'] as Map<String, dynamic>;
        options.forEach((key, value) {
          if (key == q['correct_answer']) {
            html += '<p class="correct">$key. $value ✓</p>';
          } else {
            html += '<p>$key. $value</p>';
          }
        });
        html += '</div></div>';
      }
    } else {
      html += '''
    <div class="summary">
        ${_summary.replaceAll('\n', '<br>')}
    </div>
''';
    }

    html += '</body></html>';
    return html;
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _onNavTapped(int index) {
    setState(() {
      _selectedNavIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AppBar(
              backgroundColor: Colors.white.withOpacity(0.15),
              elevation: 0,
              title: Text('مولد الأسئلة',
                  style: GoogleFonts.rubik(fontWeight: FontWeight.bold)),
              actions: [
                IconButton(
                    icon: Icon(Icons.settings),
                    onPressed: () => _showSettings(context))
              ],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // خلفية متدرجة عصرية
          AnimatedContainer(
            duration: Duration(seconds: 2),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF2196F3),
                  Color(0xFF6DD5FA),
                  Color(0xFFffffff)
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: _selectedNavIndex == 0
                    ? _buildMainContent()
                    : _buildSidebar(),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _questions.isNotEmpty || _summary.isNotEmpty
          ? FloatingActionButton.extended(
              backgroundColor: Theme.of(context).colorScheme.primary,
              icon: const Icon(Icons.download, color: Colors.white),
              label:
                  Text('تصدير', style: GoogleFonts.cairo(color: Colors.white)),
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(24))),
                  builder: (context) => _buildExportSheet(),
                );
              },
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedNavIndex,
        onTap: _onNavTapped,
        backgroundColor: Colors.white.withOpacity(0.95),
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey,
        selectedLabelStyle: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'الرئيسية',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'الإعدادات',
          ),
        ],
      ),
    );
  }

  Widget _buildExportSheet() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('تصدير النتائج',
              style:
                  GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.code, color: Colors.white),
                label:
                    const Text('JSON', style: TextStyle(color: Colors.white)),
                onPressed: () {
                  _exportQuestions('json');
                  Navigator.pop(context);
                },
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.text_snippet, color: Colors.white),
                label: const Text('TXT', style: TextStyle(color: Colors.white)),
                onPressed: () {
                  _exportQuestions('txt');
                  Navigator.pop(context);
                },
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.html, color: Colors.white),
                label:
                    const Text('HTML', style: TextStyle(color: Colors.white)),
                onPressed: () {
                  _exportQuestions('html');
                  Navigator.pop(context);
                },
              ),
              if (_generationMode == "امتحان تجريبي")
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
                  label:
                      const Text('PDF', style: TextStyle(color: Colors.white)),
                  onPressed: () {
                    _generatePDF();
                    Navigator.pop(context);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '⚙️ الإعدادات',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 20),

          // مفتاح API
          Text(
            '🔑 مفتاح Gemini API',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _apiKeyController,
            decoration: InputDecoration(
              hintText: 'أدخل مفتاح API',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              isDense: true,
            ),
            obscureText: true,
          ),
          const SizedBox(height: 4),
          Text(
            'احصل على مفتاح مجاني من Google AI Studio',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),

          const SizedBox(height: 16),

          // تحذير مهم لـ PDF
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info, color: Colors.blue, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'ملاحظة مهمة',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'استخراج النص من PDF يتطلب مفتاح API ويستخدم Gemini AI لضمان دقة النتائج. للحصول على أفضل النتائج، انسخ النص مباشرة.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue.shade600,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // حالة API
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _apiKeyController.text.isNotEmpty
                  ? Colors.green.withOpacity(0.1)
                  : Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  _apiKeyController.text.isNotEmpty
                      ? Icons.check_circle
                      : Icons.error,
                  color: _apiKeyController.text.isNotEmpty
                      ? Colors.green
                      : Colors.red,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  _apiKeyController.text.isNotEmpty ? '✅ متصل' : '❌ غير متصل',
                  style: TextStyle(
                    fontSize: 12,
                    color: _apiKeyController.text.isNotEmpty
                        ? Colors.green
                        : Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // معلومات النص
          if (_textController.text.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '📊 معلومات النص',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('📏 الطول: ${_textController.text.length} حرف'),
                  if (_detectedLanguage.isNotEmpty)
                    Text('🌐 اللغة: $_detectedLanguage'),
                ],
              ),
            ),
          ],

          const Spacer(),

          // نصائح
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .secondaryContainer
                  .withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '💡 نصائح:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '• لـ PDF: تأكد من إدخال API key أولاً\n• استخدم نصوص واضحة ومفهومة\n• ابدأ بعدد قليل من الأسئلة للتجربة\n• راجع النتائج قبل الاستخدام',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(
          icon,
          size: 20,
          color: Theme.of(context).colorScheme.secondary,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

// دالة لإنشاء صفوف المعلومات متعددة اللغات
  pw.Widget _buildInfoRowMultiLang(String label, String value,
      pw.Font regularFont, pw.Font boldFont, bool isRTL) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 120,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                font: boldFont,
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey700,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                font: regularFont,
                fontSize: 14,
                color: PdfColors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

// دالة للحصول على النصوص حسب اللغة
  Map<String, String> _getTextsForLanguage(String language) {
    switch (language) {
      case 'العربية':
      case 'ar':
        return {
          'examTitle': 'امتحان تجريبي',
          'generatedBy': 'تم إنشاؤه بواسطة مولد الأسئلة الذكي',
          'examInfo': 'معلومات الامتحان:',
          'questionsCount': 'عدد الأسئلة:',
          'question': 'سؤال',
          'difficulty': 'مستوى الصعوبة:',
          'language': 'اللغة:',
          'date': 'التاريخ:',
          'estimatedTime': 'الوقت المقدر:',
          'minute': 'دقيقة',
          'importantInstructions': 'تعليمات مهمة:',
          'goodLuck': 'بالتوفيق! 🌟',
          'page': 'صفحة',
          'questions': 'الأسئلة',
          'to': 'إلى',
          'name': 'الاسم',
          'chooseCorrectAnswer': 'اختر الإجابة الصحيحة:',
          'myAnswer': 'إجابتي:',
          'answer': 'الإجابة:',
          'of': 'من',
          'answerSheet': 'ورقة الإجابات النموذجية',
          'forTeacherOnly': 'للمدرس فقط - لا تُعطى للطلاب',
          'correctAnswer': 'الإجابة الصحيحة:',
          'explanation': 'الشرح:',
          'pdfDownloaded': 'تم تحميل ملف PDF بنجاح!',
          'fileSaved': 'تم حفظ الملف في',
          'shareDialog': 'تم فتح نافذة المشاركة لحفظ الملف',
          'pdfError': 'خطأ في إنشاء PDF',
        };
      case 'Français':
      case 'fr':
        return {
          'examTitle': 'Examen Pratique',
          'generatedBy': 'Généré par le générateur de questions intelligent',
          'examInfo': 'Informations sur l\'examen:',
          'questionsCount': 'Nombre de questions:',
          'question': 'question',
          'difficulty': 'Niveau de difficulté:',
          'language': 'Langue:',
          'date': 'Date:',
          'estimatedTime': 'Temps estimé:',
          'minute': 'minute',
          'importantInstructions': 'Instructions importantes:',
          'goodLuck': 'Bonne chance! 🌟',
          'page': 'Page',
          'questions': 'Questions',
          'to': 'à',
          'name': 'Nom',
          'chooseCorrectAnswer': 'Choisissez la bonne réponse:',
          'myAnswer': 'Ma réponse:',
          'answer': 'Réponse:',
          'of': 'de',
          'answerSheet': 'Feuille de réponses modèles',
          'forTeacherOnly':
              'Pour l\'enseignant seulement - Ne pas donner aux étudiants',
          'correctAnswer': 'Réponse correcte:',
          'explanation': 'Explication:',
          'pdfDownloaded': 'Fichier PDF téléchargé avec succès!',
          'fileSaved': 'Fichier sauvegardé dans',
          'shareDialog':
              'Dialogue de partage ouvert pour sauvegarder le fichier',
          'pdfError': 'Erreur lors de la création du PDF',
        };
      case 'English':
      case 'en':
      default:
        return {
          'examTitle': 'Practice Exam',
          'generatedBy': 'Generated by Intelligent Question Generator',
          'examInfo': 'Exam Information:',
          'questionsCount': 'Number of questions:',
          'question': 'question',
          'difficulty': 'Difficulty level:',
          'language': 'Language:',
          'date': 'Date:',
          'estimatedTime': 'Estimated time:',
          'minute': 'minute',
          'importantInstructions': 'Important Instructions:',
          'goodLuck': 'Good luck! 🌟',
          'page': 'Page',
          'questions': 'Questions',
          'to': 'to',
          'name': 'Name',
          'chooseCorrectAnswer': 'Choose the correct answer:',
          'myAnswer': 'My answer:',
          'answer': 'Answer:',
          'of': 'of',
          'answerSheet': 'Model Answer Sheet',
          'forTeacherOnly': 'For teacher only - Do not give to students',
          'correctAnswer': 'Correct answer:',
          'explanation': 'Explanation:',
          'pdfDownloaded': 'PDF file downloaded successfully!',
          'fileSaved': 'File saved in',
          'shareDialog': 'Share dialog opened to save file',
          'pdfError': 'Error creating PDF',
        };
    }
  }

// دالة للحصول على التعليمات حسب اللغة
  List<String> _getInstructionsForLanguage(
      String language, int questionsCount) {
    switch (language) {
      case 'العربية':
      case 'ar':
        return [
          'اقرأ كل سؤال بعناية قبل الإجابة',
          'استخدم القلم الأزرق أو الأسود فقط',
          'تأكد من إجابتك قبل الانتقال للسؤال التالي',
          'أدر وقتك بحكمة - ${questionsCount * 3} دقيقة متاحة',
          'في حالة عدم التأكد، اختر أفضل إجابة ممكنة',
        ];
      case 'Français':
      case 'fr':
        return [
          'Lisez chaque question attentivement avant de répondre',
          'Utilisez uniquement un stylo bleu ou noir',
          'Vérifiez votre réponse avant de passer à la question suivante',
          'Gérez votre temps judicieusement - ${questionsCount * 3} minutes disponibles',
          'En cas de doute, choisissez la meilleure réponse possible',
        ];
      case 'English':
      case 'en':
      default:
        return [
          'Read each question carefully before answering',
          'Use only blue or black pen',
          'Check your answer before moving to the next question',
          'Manage your time wisely - ${questionsCount * 3} minutes available',
          'If unsure, choose the best possible answer',
        ];
    }
  }

// دالة للحصول على خيارات الإجابة حسب اللغة
  List<String> _getAnswerChoices(String language) {
    switch (language) {
      case 'العربية':
      case 'ar':
        return ['أ', 'ب', 'ج', 'د'];
      case 'Français':
      case 'fr':
        return ['A', 'B', 'C', 'D'];
      case 'English':
      case 'en':
      default:
        return ['A', 'B', 'C', 'D'];
    }
  }

// دالة لترجمة مستوى الصعوبة حسب اللغة
  String _getDifficultyInLanguage(String difficulty, String language) {
    Map<String, Map<String, String>> difficultyTranslations = {
      'سهل': {
        'العربية': 'سهل',
        'ar': 'سهل',
        'English': 'Easy',
        'en': 'Easy',
        'Français': 'Facile',
        'fr': 'Facile',
      },
      'متوسط': {
        'العربية': 'متوسط',
        'ar': 'متوسط',
        'English': 'Medium',
        'en': 'Medium',
        'Français': 'Moyen',
        'fr': 'Moyen',
      },
      'صعب': {
        'العربية': 'صعب',
        'ar': 'صعب',
        'English': 'Hard',
        'en': 'Hard',
        'Français': 'Difficile',
        'fr': 'Difficile',
      },
      'مختلط': {
        'العربية': 'مختلط',
        'ar': 'مختلط',
        'English': 'Mixed',
        'en': 'Mixed',
        'Français': 'Mixte',
        'fr': 'Mixte',
      },
    };

    return difficultyTranslations[difficulty]?[language] ?? difficulty;
  }
}

class MindMapPainter extends CustomPainter {
  final Map<String, dynamic> mindMapData;

  MindMapPainter(this.mindMapData);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final textPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    // رسم العنوان الرئيسي
    _drawCentralNode(canvas, size, mindMapData['title'] ?? '', Colors.blue);

    // رسم العقد الفرعية
    final nodes = mindMapData['nodes'] as List<dynamic>? ?? [];
    _drawNodes(canvas, size, nodes);
  }

  void _drawCentralNode(Canvas canvas, Size size, String title, Color color) {
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCenter(center: center, width: 200, height: 60);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(30)),
      paint,
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout(maxWidth: 180);
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2,
          center.dy - textPainter.height / 2),
    );
  }

  void _drawNodes(Canvas canvas, Size size, List<dynamic> nodes) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.3;

    for (int i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final angle = (2 * math.pi * i) / nodes.length;
      final nodeCenter = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );

      // رسم الخط من المركز إلى العقدة
      final linePaint = Paint()
        ..color = Colors.grey
        ..strokeWidth = 2;

      canvas.drawLine(center, nodeCenter, linePaint);

      // رسم العقدة
      final nodeColor = _parseColor(node['color'] ?? '#FF5733');
      _drawNode(canvas, nodeCenter, node['text'] ?? '', nodeColor);

      // رسم العقد الفرعية
      final children = node['children'] as List<dynamic>? ?? [];
      _drawChildNodes(canvas, nodeCenter, children, angle);
    }
  }

  void _drawNode(Canvas canvas, Offset center, String text, Color color) {
    final rect = Rect.fromCenter(center: center, width: 120, height: 40);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(20)),
      paint,
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout(maxWidth: 100);
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2,
          center.dy - textPainter.height / 2),
    );
  }

  void _drawChildNodes(Canvas canvas, Offset parentCenter,
      List<dynamic> children, double parentAngle) {
    for (int i = 0; i < children.length; i++) {
      final child = children[i];
      final childAngle = parentAngle + (i - (children.length - 1) / 2) * 0.5;
      final childCenter = Offset(
        parentCenter.dx + 80 * math.cos(childAngle),
        parentCenter.dy + 80 * math.sin(childAngle),
      );

      // رسم الخط
      final linePaint = Paint()
        ..color = Colors.grey.shade400
        ..strokeWidth = 1;

      canvas.drawLine(parentCenter, childCenter, linePaint);

      // رسم العقدة الفرعية
      final childColor = _parseColor(child['color'] ?? '#9E9E9E');
      _drawChildNode(canvas, childCenter, child['text'] ?? '', childColor);
    }
  }

  void _drawChildNode(Canvas canvas, Offset center, String text, Color color) {
    final rect = Rect.fromCenter(center: center, width: 80, height: 30);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(15)),
      paint,
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout(maxWidth: 70);
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2,
          center.dy - textPainter.height / 2),
    );
  }

  Color _parseColor(String colorString) {
    try {
      colorString = colorString.replaceAll('#', '');
      if (colorString.length == 6) {
        colorString = 'FF$colorString';
      }
      return Color(int.parse(colorString, radix: 16));
    } catch (e) {
      return Colors.blue;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
